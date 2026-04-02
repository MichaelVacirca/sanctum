# Sanctum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an audio-reactive stained glass visual engine for a nightclub 2x2 video wall, driven by live DJ audio, using Swift and Metal on macOS.

**Architecture:** Monolithic Swift/Metal macOS app with 5 modules (AudioCapture, AnalysisEngine, CompositionEngine, ShaderPipeline, DisplayManager) sharing a single render loop. Audio from DJ mixer line-in is analyzed per-frame and drives shader parameters that corrupt stained glass visuals over the course of an evening.

**Tech Stack:** Swift 6.3, Metal, Core Audio, Accelerate (vDSP), macOS 15+, Xcode 26

**Spec:** `docs/superpowers/specs/2026-04-02-sanctum-design.md`

---

## File Structure

```
sanctum/
├── Sanctum.xcodeproj/          # Xcode project (generated via xcodegen)
├── project.yml                 # XcodeGen spec
├── Sources/
│   ├── App/
│   │   ├── SanctumApp.swift           # @main entry, NSApplication setup
│   │   ├── AppDelegate.swift          # App lifecycle, window management
│   │   └── Config.swift               # Runtime config (JSON loading)
│   ├── Audio/
│   │   ├── AudioCapture.swift         # Core Audio line-in, ring buffer
│   │   ├── AnalysisEngine.swift       # FFT, band decomposition, beat detection
│   │   ├── AudioState.swift           # AudioState struct (shared data)
│   │   └── BeatDetector.swift         # Onset detection, BPM tracking
│   ├── Corruption/
│   │   ├── CorruptionEngine.swift     # Cumulative energy → corruption index
│   │   └── CorruptionPhase.swift      # Phase enum + parameter mappings
│   ├── Composition/
│   │   ├── AssetLibrary.swift         # Load/manage PNG textures
│   │   ├── SceneGraph.swift           # Panel/icon node tree
│   │   ├── CompositionEngine.swift    # Scene updates from audio state
│   │   └── Zone.swift                 # Canvas zone definitions (center, edges)
│   ├── Shaders/
│   │   ├── ShaderTypes.h              # Shared structs (Swift ↔ Metal)
│   │   ├── Composition.metal          # Pass 1: composite panels/icons
│   │   ├── Effects.metal              # Pass 2: audio-reactive effects
│   │   ├── PostProcess.metal          # Pass 3: bloom, grain, vignette
│   │   └── Common.metal               # Shared utility functions
│   ├── Display/
│   │   ├── DisplayManager.swift       # Enumerate displays, manage windows
│   │   ├── MetalRenderer.swift        # Metal device, command queue, render loop
│   │   └── GridConfig.swift           # 2x2 grid JSON config
│   └── Debug/
│       └── DebugOverlay.swift         # FPS, bands, corruption index HUD
├── Tests/
│   ├── AudioTests/
│   │   ├── AnalysisEngineTests.swift  # FFT + band decomposition with known signals
│   │   ├── BeatDetectorTests.swift    # Beat detection with known BPM tracks
│   │   └── AudioCaptureTests.swift    # Ring buffer logic
│   ├── CorruptionTests/
│   │   ├── CorruptionEngineTests.swift # Cumulative energy → index mapping
│   │   └── CorruptionPhaseTests.swift  # Phase thresholds
│   └── CompositionTests/
│       ├── SceneGraphTests.swift       # Node management
│       └── ZoneTests.swift             # Zone assignment logic
├── Resources/
│   ├── Assets/                         # Placeholder stained glass PNGs
│   ├── TestAudio/                      # WAV files for deterministic testing
│   └── grid-config.json               # Default display grid config
├── docs/
├── .claude/
│   └── CLAUDE.md
└── .gitignore
```

---

## Task 1: Project Scaffold & Metal Window

**Goal:** Xcode project that opens a Metal-backed window showing a solid color. Proves the build pipeline and Metal device initialization work.

**Files:**
- Create: `project.yml` (XcodeGen spec)
- Create: `Sources/App/SanctumApp.swift`
- Create: `Sources/App/AppDelegate.swift`
- Create: `Sources/Display/MetalRenderer.swift`
- Create: `Sources/Shaders/ShaderTypes.h`
- Create: `Sources/Shaders/Common.metal`

- [ ] **Step 1: Install XcodeGen**

```bash
brew install xcodegen
```

- [ ] **Step 2: Create XcodeGen project spec**

Create `project.yml`:

```yaml
name: Sanctum
options:
  bundleIdPrefix: com.michaelvacirca
  deploymentTarget:
    macOS: "15.0"
  xcodeVersion: "26.4"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "15.0"
    METAL_LANGUAGE_REVISION: "Metal31"
targets:
  Sanctum:
    type: application
    platform: macOS
    sources:
      - path: Sources
        excludes:
          - "**/*.md"
    resources:
      - path: Resources
        optional: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.michaelvacirca.sanctum
        INFOPLIST_VALUES: >-
          MARKETING_VERSION=0.1.0
          CURRENT_PROJECT_VERSION=1
          GENERATE_INFOPLIST_FILE=YES
          NSMicrophoneUsageDescription=Sanctum needs audio input access to analyze music for visual generation
    dependencies: []
  SanctumTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: Sanctum
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.michaelvacirca.sanctum.tests
```

- [ ] **Step 3: Create Metal shared types header**

Create `Sources/Shaders/ShaderTypes.h`:

```c
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

struct Vertex {
    simd_float2 position;
    simd_float2 texCoord;
};

struct AudioUniforms {
    float bands[4];       // sub-bass, bass, mids, highs (0-1)
    float bpm;
    float beatPhase;      // 0-1 sawtooth
    float corruptionIndex; // 0-1
    float time;
    float isBeat;         // 1.0 on beat frame, else 0.0
    float isTransient;    // 1.0 on transient frame, else 0.0
    float padding[2];     // align to 16 bytes
};

struct CompositionUniforms {
    simd_float2 canvasSize;
    uint32_t panelCount;
    uint32_t iconCount;
};

#endif
```

- [ ] **Step 4: Create Common.metal with fullscreen quad vertex shader**

Create `Sources/Shaders/Common.metal`:

```metal
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut fullscreenQuadVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2( 1,  1)
    };
    float2 texCoords[4] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Passthrough fragment — just sample a texture
fragment float4 passthroughFragment(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    return tex.sample(s, in.texCoord);
}

// Solid color fragment — for testing
fragment float4 solidColorFragment(VertexOut in [[stage_in]],
                                    constant float4 &color [[buffer(0)]]) {
    return color;
}
```

- [ ] **Step 5: Create MetalRenderer with basic render loop**

Create `Sources/Display/MetalRenderer.swift`:

```swift
import Foundation
import Metal
import MetalKit
import QuartzCore

final class MetalRenderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var passthroughPipeline: MTLRenderPipelineState!

    // Offscreen render target (full canvas)
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

    /// Render the canvas texture to a CAMetalLayer drawable
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

    /// Clear the canvas to a solid color (for testing)
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
```

- [ ] **Step 6: Create AppDelegate with Metal window**

Create `Sources/App/AppDelegate.swift`:

```swift
import Cocoa
import Metal
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var metalLayer: CAMetalLayer!
    private var renderer: MetalRenderer!
    private var displayLink: CVDisplayLink?

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

        // Clear to deep cathedral blue as proof of life
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
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.renderFrame()
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
```

- [ ] **Step 7: Create app entry point**

Create `Sources/App/SanctumApp.swift`:

```swift
import Cocoa

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

- [ ] **Step 8: Create placeholder directories and resources**

```bash
mkdir -p Resources/Assets Resources/TestAudio Tests/AudioTests Tests/CorruptionTests Tests/CompositionTests
touch Resources/Assets/.gitkeep Resources/TestAudio/.gitkeep
```

- [ ] **Step 9: Generate Xcode project and verify it builds**

```bash
cd /path/to/sanctum
xcodegen generate
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

Expected: Build succeeds. Running the app shows a window filled with deep cathedral blue.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: project scaffold with Metal window and render loop"
```

---

## Task 2: Audio Capture (Core Audio Line-In)

**Goal:** Capture audio from the system's line-in input into a ring buffer. Verify by logging RMS levels.

**Files:**
- Create: `Sources/Audio/AudioCapture.swift`
- Create: `Sources/Audio/AudioState.swift`
- Create: `Tests/AudioTests/AudioCaptureTests.swift`

- [ ] **Step 1: Create AudioState struct**

Create `Sources/Audio/AudioState.swift`:

```swift
import Foundation

struct AudioState {
    var bands: (Float, Float, Float, Float) = (0, 0, 0, 0) // sub-bass, bass, mids, highs
    var bpm: Float = 120
    var beatPhase: Float = 0    // 0-1 sawtooth synced to beat
    var isBeat: Bool = false
    var isTransient: Bool = false
    var corruptionIndex: Float = 0 // 0-1 cumulative energy arc
    var rawSpectrum: [Float] = []

    static let silent = AudioState()

    var subBass: Float { bands.0 }
    var bass: Float { bands.1 }
    var mids: Float { bands.2 }
    var highs: Float { bands.3 }
    var overallEnergy: Float { (bands.0 + bands.1 + bands.2 + bands.3) / 4.0 }
}
```

- [ ] **Step 2: Create AudioCapture with Core Audio**

Create `Sources/Audio/AudioCapture.swift`:

```swift
import Foundation
import AudioToolbox
import CoreAudio

final class AudioCapture {
    private var audioUnit: AudioComponentInstance?
    private let bufferSize: Int
    private var ringBuffer: [Float]
    private var writeIndex: Int = 0
    private let lock = NSLock()
    let sampleRate: Double

    /// Called on the audio thread with new samples
    var onSamplesAvailable: (([Float]) -> Void)?

    init(bufferSize: Int = 4096, preferredSampleRate: Double = 48000) {
        self.bufferSize = bufferSize
        self.sampleRate = preferredSampleRate
        self.ringBuffer = [Float](repeating: 0, count: bufferSize * 4) // 4x overallocation
    }

    func start() throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw SanctumError.audioDeviceNotFound
        }

        var audioUnit: AudioComponentInstance?
        AudioComponentInstanceNew(component, &audioUnit)
        guard let au = audioUnit else {
            throw SanctumError.audioDeviceNotFound
        }
        self.audioUnit = au

        // Enable input
        var enableIO: UInt32 = 1
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                            kAudioUnitScope_Input, 1,
                            &enableIO, UInt32(MemoryLayout<UInt32>.size))

        // Disable output
        var disableIO: UInt32 = 0
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                            kAudioUnitScope_Output, 0,
                            &disableIO, UInt32(MemoryLayout<UInt32>.size))

        // Set format: mono Float32
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                            kAudioUnitScope_Output, 1,
                            &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        // Set input callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback,
                            kAudioUnitScope_Global, 0,
                            &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        try checkOSStatus(AudioUnitInitialize(au))
        try checkOSStatus(AudioOutputUnitStart(au))
    }

    func stop() {
        guard let au = audioUnit else { return }
        AudioOutputUnitStop(au)
        AudioComponentInstanceDispose(au)
        audioUnit = nil
    }

    /// Get the most recent `count` samples from the ring buffer
    func getRecentSamples(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let totalSize = ringBuffer.count
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let idx = (writeIndex - count + i + totalSize) % totalSize
            result[i] = ringBuffer[idx]
        }
        return result
    }

    fileprivate func writeSamples(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            ringBuffer[writeIndex % ringBuffer.count] = sample
            writeIndex += 1
        }

        let copied = Array(samples)
        onSamplesAvailable?(copied)
    }

    private func checkOSStatus(_ status: OSStatus) throws {
        if status != noErr {
            throw SanctumError.audioDeviceNotFound
        }
    }
}

private func audioInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let capture = Unmanaged<AudioCapture>.fromOpaque(inRefCon).takeUnretainedValue()

    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 4,
            mData: nil
        )
    )

    let buffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(inNumberFrames))
    bufferList.mBuffers.mData = UnsafeMutableRawPointer(buffer)

    guard let au = capture.audioUnit else {
        buffer.deallocate()
        return noErr
    }

    let status = AudioUnitRender(au, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)

    if status == noErr {
        let bufferPointer = UnsafeBufferPointer(start: buffer, count: Int(inNumberFrames))
        capture.writeSamples(bufferPointer)
    }

    buffer.deallocate()
    return status
}
```

- [ ] **Step 3: Write ring buffer test**

Create `Tests/AudioTests/AudioCaptureTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class AudioCaptureTests: XCTestCase {

    func testRingBufferWriteAndRead() {
        let capture = AudioCapture(bufferSize: 1024)

        // Simulate writing samples directly into the ring buffer
        // by using getRecentSamples on a fresh buffer (should be zeros)
        let samples = capture.getRecentSamples(count: 512)
        XCTAssertEqual(samples.count, 512)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }

    func testAudioStateDefaults() {
        let state = AudioState.silent
        XCTAssertEqual(state.subBass, 0)
        XCTAssertEqual(state.bass, 0)
        XCTAssertEqual(state.mids, 0)
        XCTAssertEqual(state.highs, 0)
        XCTAssertEqual(state.corruptionIndex, 0)
        XCTAssertEqual(state.bpm, 120)
        XCTAssertFalse(state.isBeat)
    }

    func testOverallEnergy() {
        var state = AudioState()
        state.bands = (0.5, 0.5, 0.5, 0.5)
        XCTAssertEqual(state.overallEnergy, 0.5)

        state.bands = (1.0, 0.0, 0.5, 0.5)
        XCTAssertEqual(state.overallEnergy, 0.5)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Audio/AudioCapture.swift Sources/Audio/AudioState.swift Tests/AudioTests/AudioCaptureTests.swift
git commit -m "feat: audio capture with Core Audio line-in and ring buffer"
```

---

## Task 3: Analysis Engine (FFT + Band Decomposition)

**Goal:** Take raw audio samples, perform FFT, decompose into 4 frequency bands. Verified by feeding a known sine wave and checking the correct band lights up.

**Files:**
- Create: `Sources/Audio/AnalysisEngine.swift`
- Create: `Tests/AudioTests/AnalysisEngineTests.swift`

- [ ] **Step 1: Write failing test for band decomposition**

Create `Tests/AudioTests/AnalysisEngineTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class AnalysisEngineTests: XCTestCase {

    func testSilenceProducesZeroBands() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let silence = [Float](repeating: 0, count: 4096)
        let state = engine.analyze(samples: silence)

        XCTAssertEqual(state.subBass, 0, accuracy: 0.01)
        XCTAssertEqual(state.bass, 0, accuracy: 0.01)
        XCTAssertEqual(state.mids, 0, accuracy: 0.01)
        XCTAssertEqual(state.highs, 0, accuracy: 0.01)
    }

    func testSubBassDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        // Generate 50Hz sine wave (sub-bass range: 20-80Hz)
        let samples = generateSineWave(frequency: 50, sampleRate: 48000, count: 4096)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.subBass, 0.3, "Sub-bass should be dominant")
        XCTAssertGreaterThan(state.subBass, state.mids, "Sub-bass should exceed mids")
        XCTAssertGreaterThan(state.subBass, state.highs, "Sub-bass should exceed highs")
    }

    func testBassDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        // Generate 150Hz sine wave (bass range: 80-250Hz)
        let samples = generateSineWave(frequency: 150, sampleRate: 48000, count: 4096)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.bass, 0.3, "Bass should be dominant")
        XCTAssertGreaterThan(state.bass, state.subBass, "Bass should exceed sub-bass")
    }

    func testMidsDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        // Generate 1000Hz sine wave (mids range: 250-4000Hz)
        let samples = generateSineWave(frequency: 1000, sampleRate: 48000, count: 4096)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.mids, 0.3, "Mids should be dominant")
        XCTAssertGreaterThan(state.mids, state.subBass, "Mids should exceed sub-bass")
    }

    func testHighsDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        // Generate 8000Hz sine wave (highs range: 4000-20000Hz)
        let samples = generateSineWave(frequency: 8000, sampleRate: 48000, count: 4096)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.highs, 0.3, "Highs should be dominant")
        XCTAssertGreaterThan(state.highs, state.subBass, "Highs should exceed sub-bass")
    }

    func testSpectrumLength() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let samples = [Float](repeating: 0, count: 4096)
        let state = engine.analyze(samples: samples)
        XCTAssertEqual(state.rawSpectrum.count, 2048) // N/2 bins
    }

    // MARK: - Helpers

    private func generateSineWave(frequency: Float, sampleRate: Float, count: Int) -> [Float] {
        (0..<count).map { i in
            sinf(2.0 * .pi * frequency * Float(i) / sampleRate)
        }
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: FAIL — `AnalysisEngine` not found.

- [ ] **Step 3: Implement AnalysisEngine**

Create `Sources/Audio/AnalysisEngine.swift`:

```swift
import Foundation
import Accelerate

final class AnalysisEngine {
    private let sampleRate: Float
    private let fftSize: Int
    private let fftSetup: vDSP.FFT<DSPSplitComplex>
    private let windowBuffer: [Float]

    // Band boundaries in Hz
    private let subBassRange: ClosedRange<Float> = 20...80
    private let bassRange: ClosedRange<Float> = 80...250
    private let midsRange: ClosedRange<Float> = 250...4000
    private let highsRange: ClosedRange<Float> = 4000...20000

    // Smoothing
    private var smoothedBands: (Float, Float, Float, Float) = (0, 0, 0, 0)
    private let smoothingFactor: Float = 0.3 // lower = smoother

    init(sampleRate: Float = 48000, fftSize: Int = 4096) {
        self.sampleRate = sampleRate
        self.fftSize = fftSize

        let log2n = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!

        // Hann window for smoother spectrum
        self.windowBuffer = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    }

    func analyze(samples: [Float]) -> AudioState {
        guard samples.count >= fftSize else {
            return .silent
        }

        // Apply window
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP.multiply(samples.prefix(fftSize).map { $0 }, windowBuffer, result: &windowed)

        // Perform FFT
        let magnitudes = performFFT(windowed)

        // Decompose into bands
        let subBass = bandEnergy(magnitudes: magnitudes, range: subBassRange)
        let bass = bandEnergy(magnitudes: magnitudes, range: bassRange)
        let mids = bandEnergy(magnitudes: magnitudes, range: midsRange)
        let highs = bandEnergy(magnitudes: magnitudes, range: highsRange)

        // Smooth
        smoothedBands.0 = lerp(smoothedBands.0, subBass, t: smoothingFactor)
        smoothedBands.1 = lerp(smoothedBands.1, bass, t: smoothingFactor)
        smoothedBands.2 = lerp(smoothedBands.2, mids, t: smoothingFactor)
        smoothedBands.3 = lerp(smoothedBands.3, highs, t: smoothingFactor)

        var state = AudioState()
        state.bands = smoothedBands
        state.rawSpectrum = magnitudes
        return state
    }

    private func performFFT(_ samples: [Float]) -> [Float] {
        let halfN = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        samples.withUnsafeBufferPointer { samplesPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    // Convert interleaved to split complex
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                    // Forward FFT
                    fftSetup.forward(input: splitComplex, output: &splitComplex)
                }
            }
        }

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeBufferPointer { realPtr in
            imagPart.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Convert to dB-like scale, normalize
        vDSP.squareRoots(magnitudes, result: &magnitudes)
        let scale = 2.0 / Float(fftSize)
        vDSP.multiply(scale, magnitudes, result: &magnitudes)

        return magnitudes
    }

    private func bandEnergy(magnitudes: [Float], range: ClosedRange<Float>) -> Float {
        let binResolution = sampleRate / Float(fftSize)
        let startBin = max(0, Int(range.lowerBound / binResolution))
        let endBin = min(magnitudes.count - 1, Int(range.upperBound / binResolution))

        guard startBin < endBin else { return 0 }

        let slice = magnitudes[startBin...endBin]
        let rms = sqrt(slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count))

        // Normalize to 0-1 range (empirical scaling)
        return min(rms * 10.0, 1.0)
    }

    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Audio/AnalysisEngine.swift Tests/AudioTests/AnalysisEngineTests.swift
git commit -m "feat: FFT analysis engine with 4-band decomposition"
```

---

## Task 4: Beat Detection & BPM Tracking

**Goal:** Detect beat onsets (kicks) and track BPM from the audio signal.

**Files:**
- Create: `Sources/Audio/BeatDetector.swift`
- Create: `Tests/AudioTests/BeatDetectorTests.swift`
- Modify: `Sources/Audio/AnalysisEngine.swift` (integrate beat detector)

- [ ] **Step 1: Write failing test for beat detection**

Create `Tests/AudioTests/BeatDetectorTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class BeatDetectorTests: XCTestCase {

    func testSilenceProducesNoBeats() {
        let detector = BeatDetector(sampleRate: 48000)
        let result = detector.process(bassEnergy: 0, overallEnergy: 0, deltaTime: 1.0 / 60.0)
        XCTAssertFalse(result.isBeat)
        XCTAssertFalse(result.isTransient)
    }

    func testSuddenEnergySpikeTriggersBeat() {
        let detector = BeatDetector(sampleRate: 48000)

        // Feed low energy for a bit
        for _ in 0..<30 {
            _ = detector.process(bassEnergy: 0.05, overallEnergy: 0.1, deltaTime: 1.0 / 60.0)
        }

        // Sudden spike
        let result = detector.process(bassEnergy: 0.9, overallEnergy: 0.8, deltaTime: 1.0 / 60.0)
        XCTAssertTrue(result.isBeat, "A large sudden bass spike should trigger a beat")
    }

    func testBeatPhaseRamps() {
        let detector = BeatDetector(sampleRate: 48000)
        detector.currentBPM = 120 // 2 beats per second

        let r1 = detector.process(bassEnergy: 0.05, overallEnergy: 0.1, deltaTime: 0.25)
        // At 120 BPM, 0.25 seconds = half a beat
        XCTAssertEqual(r1.beatPhase, 0.5, accuracy: 0.1)
    }

    func testTransientDetectsLargeOverallSpike() {
        let detector = BeatDetector(sampleRate: 48000)

        // Build up moderate energy
        for _ in 0..<60 {
            _ = detector.process(bassEnergy: 0.3, overallEnergy: 0.3, deltaTime: 1.0 / 60.0)
        }

        // Massive spike (a drop)
        let result = detector.process(bassEnergy: 0.95, overallEnergy: 0.95, deltaTime: 1.0 / 60.0)
        XCTAssertTrue(result.isTransient)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: FAIL — `BeatDetector` not found.

- [ ] **Step 3: Implement BeatDetector**

Create `Sources/Audio/BeatDetector.swift`:

```swift
import Foundation

struct BeatResult {
    let isBeat: Bool
    let isTransient: Bool
    let beatPhase: Float
    let bpm: Float
}

final class BeatDetector {
    private let sampleRate: Float

    // Beat detection state
    var currentBPM: Float = 120
    private var beatPhaseAccumulator: Float = 0
    private var bassHistory: [Float] = []
    private var energyHistory: [Float] = []
    private let historySize = 120 // ~2 seconds at 60fps
    private var lastBeatTime: Double = 0
    private var beatIntervals: [Double] = []
    private let maxIntervals = 16

    // Thresholds
    private let beatThresholdMultiplier: Float = 1.8
    private let transientThresholdMultiplier: Float = 2.5
    private let minBeatInterval: Double = 0.2 // 300 BPM max

    private var elapsedTime: Double = 0

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
    }

    func process(bassEnergy: Float, overallEnergy: Float, deltaTime: Float) -> BeatResult {
        elapsedTime += Double(deltaTime)

        // Update history
        bassHistory.append(bassEnergy)
        energyHistory.append(overallEnergy)
        if bassHistory.count > historySize { bassHistory.removeFirst() }
        if energyHistory.count > historySize { energyHistory.removeFirst() }

        // Beat detection: bass energy exceeds recent average by threshold
        let bassAvg = bassHistory.reduce(0, +) / Float(bassHistory.count)
        let isBeat = bassEnergy > bassAvg * beatThresholdMultiplier
                     && bassEnergy > 0.15
                     && (elapsedTime - lastBeatTime) > minBeatInterval

        // Update BPM from beat intervals
        if isBeat {
            let interval = elapsedTime - lastBeatTime
            if interval > minBeatInterval && interval < 2.0 {
                beatIntervals.append(interval)
                if beatIntervals.count > maxIntervals { beatIntervals.removeFirst() }
                if beatIntervals.count >= 4 {
                    let avgInterval = beatIntervals.reduce(0, +) / Double(beatIntervals.count)
                    currentBPM = Float(60.0 / avgInterval)
                }
            }
            lastBeatTime = elapsedTime
            beatPhaseAccumulator = 0
        }

        // Transient detection: overall energy spike
        let energyAvg = energyHistory.reduce(0, +) / Float(energyHistory.count)
        let isTransient = overallEnergy > energyAvg * transientThresholdMultiplier
                          && overallEnergy > 0.5

        // Advance beat phase
        let beatsPerSecond = currentBPM / 60.0
        beatPhaseAccumulator += deltaTime * beatsPerSecond
        let phase = beatPhaseAccumulator.truncatingRemainder(dividingBy: 1.0)

        return BeatResult(
            isBeat: isBeat,
            isTransient: isTransient,
            beatPhase: phase,
            bpm: currentBPM
        )
    }

    func reset() {
        bassHistory.removeAll()
        energyHistory.removeAll()
        beatIntervals.removeAll()
        beatPhaseAccumulator = 0
        lastBeatTime = 0
        elapsedTime = 0
        currentBPM = 120
    }
}
```

- [ ] **Step 4: Integrate BeatDetector into AnalysisEngine**

Add to `Sources/Audio/AnalysisEngine.swift`:

```swift
// Add property:
private let beatDetector = BeatDetector()

// In analyze(), after computing bands and before return:
let beatResult = beatDetector.process(
    bassEnergy: subBass,
    overallEnergy: (subBass + bass + mids + highs) / 4.0,
    deltaTime: Float(fftSize) / sampleRate // approximate frame time from samples
)
state.isBeat = beatResult.isBeat
state.isTransient = beatResult.isTransient
state.beatPhase = beatResult.beatPhase
state.bpm = beatResult.bpm
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: All tests pass (AudioCapture + AnalysisEngine + BeatDetector).

- [ ] **Step 6: Commit**

```bash
git add Sources/Audio/BeatDetector.swift Tests/AudioTests/BeatDetectorTests.swift Sources/Audio/AnalysisEngine.swift
git commit -m "feat: beat detection and BPM tracking"
```

---

## Task 5: Corruption Engine

**Goal:** Track cumulative audio energy and map it to a 0→1 corruption index with 5 named phases.

**Files:**
- Create: `Sources/Corruption/CorruptionPhase.swift`
- Create: `Sources/Corruption/CorruptionEngine.swift`
- Create: `Tests/CorruptionTests/CorruptionPhaseTests.swift`
- Create: `Tests/CorruptionTests/CorruptionEngineTests.swift`

- [ ] **Step 1: Write failing tests for corruption phase**

Create `Tests/CorruptionTests/CorruptionPhaseTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class CorruptionPhaseTests: XCTestCase {

    func testPhaseFromCorruptionIndex() {
        XCTAssertEqual(CorruptionPhase.from(index: 0.0), .sacred)
        XCTAssertEqual(CorruptionPhase.from(index: 0.1), .sacred)
        XCTAssertEqual(CorruptionPhase.from(index: 0.2), .awakening)
        XCTAssertEqual(CorruptionPhase.from(index: 0.3), .awakening)
        XCTAssertEqual(CorruptionPhase.from(index: 0.5), .fracture)
        XCTAssertEqual(CorruptionPhase.from(index: 0.7), .profane)
        XCTAssertEqual(CorruptionPhase.from(index: 0.9), .abyss)
        XCTAssertEqual(CorruptionPhase.from(index: 1.0), .abyss)
    }

    func testPhaseLocalProgress() {
        // At 0.3 (middle of awakening 0.2-0.4), local progress should be 0.5
        let progress = CorruptionPhase.localProgress(at: 0.3)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Write failing tests for corruption engine**

Create `Tests/CorruptionTests/CorruptionEngineTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class CorruptionEngineTests: XCTestCase {

    func testStartsAtZero() {
        let engine = CorruptionEngine(windowDuration: 3600)
        XCTAssertEqual(engine.corruptionIndex, 0, accuracy: 0.001)
    }

    func testAccumulatesEnergy() {
        let engine = CorruptionEngine(windowDuration: 100) // short window for testing
        // Feed high energy for some time
        for _ in 0..<60 {
            engine.update(energy: 1.0, deltaTime: 1.0)
        }
        XCTAssertGreaterThan(engine.corruptionIndex, 0)
        XCTAssertLessThanOrEqual(engine.corruptionIndex, 1.0)
    }

    func testSilenceDoesNotIncrease() {
        let engine = CorruptionEngine(windowDuration: 3600)
        engine.update(energy: 0, deltaTime: 1.0)
        engine.update(energy: 0, deltaTime: 1.0)
        XCTAssertEqual(engine.corruptionIndex, 0, accuracy: 0.001)
    }

    func testClampsAtOne() {
        let engine = CorruptionEngine(windowDuration: 10)
        for _ in 0..<1000 {
            engine.update(energy: 1.0, deltaTime: 1.0)
        }
        XCTAssertEqual(engine.corruptionIndex, 1.0, accuracy: 0.001)
    }

    func testReset() {
        let engine = CorruptionEngine(windowDuration: 100)
        for _ in 0..<50 {
            engine.update(energy: 1.0, deltaTime: 1.0)
        }
        XCTAssertGreaterThan(engine.corruptionIndex, 0)
        engine.reset()
        XCTAssertEqual(engine.corruptionIndex, 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 3: Run tests — verify they fail**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: FAIL — types not found.

- [ ] **Step 4: Implement CorruptionPhase**

Create `Sources/Corruption/CorruptionPhase.swift`:

```swift
import Foundation

enum CorruptionPhase: String, CaseIterable {
    case sacred     // 0.0 - 0.2
    case awakening  // 0.2 - 0.4
    case fracture   // 0.4 - 0.6
    case profane    // 0.6 - 0.8
    case abyss      // 0.8 - 1.0

    static func from(index: Float) -> CorruptionPhase {
        switch index {
        case ..<0.2: return .sacred
        case ..<0.4: return .awakening
        case ..<0.6: return .fracture
        case ..<0.8: return .profane
        default: return .abyss
        }
    }

    /// Progress within the current phase (0-1)
    static func localProgress(at index: Float) -> Float {
        let clamped = max(0, min(1, index))
        let phaseStart = (clamped / 0.2).rounded(.down) * 0.2
        return (clamped - phaseStart) / 0.2
    }

    var range: ClosedRange<Float> {
        switch self {
        case .sacred: return 0...0.2
        case .awakening: return 0.2...0.4
        case .fracture: return 0.4...0.6
        case .profane: return 0.6...0.8
        case .abyss: return 0.8...1.0
        }
    }
}
```

- [ ] **Step 5: Implement CorruptionEngine**

Create `Sources/Corruption/CorruptionEngine.swift`:

```swift
import Foundation

final class CorruptionEngine {
    /// How many seconds of max energy to reach corruption 1.0
    private let windowDuration: Double

    private var cumulativeEnergy: Double = 0
    private(set) var corruptionIndex: Float = 0

    var currentPhase: CorruptionPhase {
        CorruptionPhase.from(index: corruptionIndex)
    }

    var localProgress: Float {
        CorruptionPhase.localProgress(at: corruptionIndex)
    }

    init(windowDuration: Double = 18000) { // default 5 hours
        self.windowDuration = windowDuration
    }

    func update(energy: Float, deltaTime: Float) {
        // Accumulate energy over time
        cumulativeEnergy += Double(energy) * Double(deltaTime)
        // Normalize to 0-1 over the window
        corruptionIndex = min(1.0, Float(cumulativeEnergy / windowDuration))
    }

    func reset() {
        cumulativeEnergy = 0
        corruptionIndex = 0
    }
}
```

- [ ] **Step 6: Run tests — verify they pass**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Corruption/ Tests/CorruptionTests/
git commit -m "feat: corruption engine with 5-phase arc driven by cumulative energy"
```

---

## Task 6: Asset Loading & Texture Management

**Goal:** Load PNG images into Metal textures. Create placeholder stained glass test assets. Render a textured quad to screen.

**Files:**
- Create: `Sources/Composition/AssetLibrary.swift`
- Create: placeholder test assets in `Resources/Assets/`
- Modify: `Sources/Display/MetalRenderer.swift` (add texture rendering)

- [ ] **Step 1: Create placeholder test assets**

Generate simple colored PNG files as placeholders (256x256):

```bash
# Use sips to create solid color test images
# We'll create proper stained glass art later — these are just for pipeline testing
python3 -c "
from PIL import Image
# Deep blue panel
img = Image.new('RGBA', (256, 256), (15, 10, 60, 255))
img.save('Resources/Assets/test-panel-blue.png')
# Ruby red panel
img = Image.new('RGBA', (256, 256), (140, 20, 30, 255))
img.save('Resources/Assets/test-panel-red.png')
# Gold icon (with transparency)
img = Image.new('RGBA', (128, 128), (200, 170, 50, 200))
img.save('Resources/Assets/test-icon-gold.png')
"
```

If Python/PIL not available, create them programmatically in Swift during tests, or use any available PNG files.

- [ ] **Step 2: Implement AssetLibrary**

Create `Sources/Composition/AssetLibrary.swift`:

```swift
import Foundation
import Metal
import MetalKit

final class AssetLibrary {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    private var textures: [String: MTLTexture] = [:]

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    /// Load all PNG/EXR assets from a directory
    func loadAssets(from directory: URL) throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)

        for file in files where file.pathExtension == "png" || file.pathExtension == "exr" {
            let name = file.deletingPathExtension().lastPathComponent
            let texture = try loadTexture(from: file)
            textures[name] = texture
        }
    }

    /// Load a single texture from a URL
    func loadTexture(from url: URL) throws -> MTLTexture {
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage([.shaderRead]).rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .generateMipmaps: true,
            .SRGB: false
        ]
        return try textureLoader.newTexture(URL: url, options: options)
    }

    /// Get a loaded texture by name
    func texture(named name: String) -> MTLTexture? {
        textures[name]
    }

    /// All loaded texture names
    var textureNames: [String] {
        Array(textures.keys)
    }

    /// Number of loaded textures
    var count: Int {
        textures.count
    }

    /// Create a solid-color texture (useful for testing without image files)
    func createSolidTexture(width: Int, height: Int,
                            color: (UInt8, UInt8, UInt8, UInt8),
                            name: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = color.2     // B
            pixels[i+1] = color.1   // G
            pixels[i+2] = color.0   // R
            pixels[i+3] = color.3   // A
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow
        )

        textures[name] = texture
        return texture
    }
}
```

- [ ] **Step 3: Add texture rendering to MetalRenderer**

Add to `Sources/Display/MetalRenderer.swift`:

```swift
// Add method to render a texture to the canvas
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
```

- [ ] **Step 4: Verify — update AppDelegate to display a test texture**

Temporarily update `AppDelegate.applicationDidFinishLaunching` to load and display a test asset:

```swift
// After renderer init, add:
let assetLibrary = AssetLibrary(device: renderer.device)
assetLibrary.createSolidTexture(width: 256, height: 256,
    color: (15, 10, 60, 255), name: "test-panel")
if let tex = assetLibrary.texture(named: "test-panel") {
    renderer.renderTextureToCanvas(tex)
}
```

- [ ] **Step 5: Build and run — verify texture appears**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

Expected: Window shows the solid blue texture stretched to fill. Proves the texture pipeline works.

- [ ] **Step 6: Commit**

```bash
git add Sources/Composition/AssetLibrary.swift Sources/Display/MetalRenderer.swift Resources/Assets/
git commit -m "feat: asset library with Metal texture loading"
```

---

## Task 7: Scene Graph & Composition Engine

**Goal:** Manage a tree of visual nodes (panels, icons) that can be positioned, layered, and transitioned based on audio state.

**Files:**
- Create: `Sources/Composition/Zone.swift`
- Create: `Sources/Composition/SceneGraph.swift`
- Create: `Sources/Composition/CompositionEngine.swift`
- Create: `Tests/CompositionTests/SceneGraphTests.swift`
- Create: `Tests/CompositionTests/ZoneTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/CompositionTests/ZoneTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class ZoneTests: XCTestCase {

    func testCenterZoneContainsCenterPoint() {
        let zone = Zone.center(canvasWidth: 3840, canvasHeight: 2160)
        XCTAssertTrue(zone.contains(x: 1920, y: 1080))
    }

    func testEdgeZonesExist() {
        let zones = Zone.allZones(canvasWidth: 3840, canvasHeight: 2160)
        XCTAssertEqual(zones.count, 5) // center + 4 edges
    }
}
```

Create `Tests/CompositionTests/SceneGraphTests.swift`:

```swift
import XCTest
@testable import Sanctum

final class SceneGraphTests: XCTestCase {

    func testAddAndRemoveNodes() {
        let graph = SceneGraph()
        let node = SceneNode(id: "panel-1", type: .panel, textureName: "test")
        graph.addNode(node)
        XCTAssertEqual(graph.nodeCount, 1)
        graph.removeNode(id: "panel-1")
        XCTAssertEqual(graph.nodeCount, 0)
    }

    func testNodesOrderedByZIndex() {
        let graph = SceneGraph()
        let back = SceneNode(id: "bg", type: .panel, textureName: "bg", zIndex: 0)
        let front = SceneNode(id: "icon", type: .icon, textureName: "saint", zIndex: 10)
        graph.addNode(front)
        graph.addNode(back)
        let ordered = graph.orderedNodes
        XCTAssertEqual(ordered[0].id, "bg")
        XCTAssertEqual(ordered[1].id, "icon")
    }

    func testNodeTransformUpdate() {
        let graph = SceneGraph()
        var node = SceneNode(id: "p1", type: .panel, textureName: "test")
        node.position = (100, 200)
        node.scale = 1.5
        node.opacity = 0.8
        graph.addNode(node)

        let retrieved = graph.node(id: "p1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.position.x, 100)
        XCTAssertEqual(retrieved?.scale, 1.5)
        XCTAssertEqual(retrieved?.opacity, 0.8)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

- [ ] **Step 3: Implement Zone**

Create `Sources/Composition/Zone.swift`:

```swift
import Foundation

struct Zone {
    let name: String
    let rect: (x: Float, y: Float, width: Float, height: Float)
    let effectIntensity: Float // 1.0 = full effects (center), 0.5 = subtle (edges)

    func contains(x: Float, y: Float) -> Bool {
        x >= rect.x && x <= rect.x + rect.width &&
        y >= rect.y && y <= rect.y + rect.height
    }

    static func center(canvasWidth: Float, canvasHeight: Float) -> Zone {
        let w = canvasWidth * 0.5
        let h = canvasHeight * 0.5
        return Zone(
            name: "center",
            rect: (x: canvasWidth * 0.25, y: canvasHeight * 0.25, width: w, height: h),
            effectIntensity: 1.0
        )
    }

    static func allZones(canvasWidth: Float, canvasHeight: Float) -> [Zone] {
        let cw = canvasWidth
        let ch = canvasHeight
        return [
            center(canvasWidth: cw, canvasHeight: ch),
            Zone(name: "top", rect: (0, 0, cw, ch * 0.25), effectIntensity: 0.5),
            Zone(name: "bottom", rect: (0, ch * 0.75, cw, ch * 0.25), effectIntensity: 0.5),
            Zone(name: "left", rect: (0, ch * 0.25, cw * 0.25, ch * 0.5), effectIntensity: 0.6),
            Zone(name: "right", rect: (cw * 0.75, ch * 0.25, cw * 0.25, ch * 0.5), effectIntensity: 0.6),
        ]
    }
}
```

- [ ] **Step 4: Implement SceneGraph and SceneNode**

Create `Sources/Composition/SceneGraph.swift`:

```swift
import Foundation

enum NodeType {
    case panel
    case icon
    case texture
}

struct SceneNode {
    let id: String
    let type: NodeType
    let textureName: String
    var position: (x: Float, y: Float) = (0, 0)
    var scale: Float = 1.0
    var rotation: Float = 0 // radians
    var opacity: Float = 1.0
    var zIndex: Int = 0
    var zoneName: String? = nil

    // Animation targets (lerp toward these)
    var targetPosition: (x: Float, y: Float)?
    var targetScale: Float?
    var targetOpacity: Float?
}

final class SceneGraph {
    private var nodes: [String: SceneNode] = [:]

    var nodeCount: Int { nodes.count }

    var orderedNodes: [SceneNode] {
        nodes.values.sorted { $0.zIndex < $1.zIndex }
    }

    func addNode(_ node: SceneNode) {
        nodes[node.id] = node
    }

    func removeNode(id: String) {
        nodes.removeValue(forKey: id)
    }

    func node(id: String) -> SceneNode? {
        nodes[id]
    }

    func updateNode(id: String, _ transform: (inout SceneNode) -> Void) {
        guard var node = nodes[id] else { return }
        transform(&node)
        nodes[id] = node
    }

    /// Animate all nodes toward their targets
    func animate(deltaTime: Float, speed: Float = 2.0) {
        let t = min(1.0, deltaTime * speed)
        for (id, node) in nodes {
            var n = node
            if let target = n.targetPosition {
                n.position.x += (target.x - n.position.x) * t
                n.position.y += (target.y - n.position.y) * t
            }
            if let target = n.targetScale {
                n.scale += (target - n.scale) * t
            }
            if let target = n.targetOpacity {
                n.opacity += (target - n.opacity) * t
            }
            nodes[id] = n
        }
    }

    func allNodes(ofType type: NodeType) -> [SceneNode] {
        nodes.values.filter { $0.type == type }
    }
}
```

- [ ] **Step 5: Implement CompositionEngine**

Create `Sources/Composition/CompositionEngine.swift`:

```swift
import Foundation

final class CompositionEngine {
    let sceneGraph = SceneGraph()
    private let zones: [Zone]
    private let canvasWidth: Float
    private let canvasHeight: Float
    private var panelNames: [String] = []
    private var iconNames: [String] = []
    private var activePanelIndices: [Int] = []
    private var lastTransitionEnergy: Float = 0

    init(canvasWidth: Float = 3840, canvasHeight: Float = 2160) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.zones = Zone.allZones(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    }

    /// Register available panel texture names
    func setPanels(_ names: [String]) {
        self.panelNames = names
        // Initialize with first 4 panels in the 2x2 grid
        let initialPanels = Array(names.prefix(4))
        for (i, name) in initialPanels.enumerated() {
            let col = Float(i % 2)
            let row = Float(i / 2)
            let node = SceneNode(
                id: "panel-\(i)",
                type: .panel,
                textureName: name,
                position: (col * canvasWidth / 2, row * canvasHeight / 2),
                scale: 1.0,
                opacity: 1.0,
                zIndex: 0
            )
            sceneGraph.addNode(node)
            activePanelIndices.append(i)
        }
    }

    /// Register available icon texture names
    func setIcons(_ names: [String]) {
        self.iconNames = names
        // Place a few icons initially
        for (i, name) in names.prefix(6).enumerated() {
            let node = SceneNode(
                id: "icon-\(i)",
                type: .icon,
                textureName: name,
                position: (
                    Float.random(in: canvasWidth * 0.2...canvasWidth * 0.8),
                    Float.random(in: canvasHeight * 0.2...canvasHeight * 0.8)
                ),
                scale: 0.3,
                opacity: 0.9,
                zIndex: 10 + i
            )
            sceneGraph.addNode(node)
        }
    }

    /// Update scene based on current audio state
    func update(audioState: AudioState, deltaTime: Float) {
        // Animate existing nodes
        sceneGraph.animate(deltaTime: deltaTime)

        // Drift icons slowly
        for node in sceneGraph.allNodes(ofType: .icon) {
            sceneGraph.updateNode(id: node.id) { n in
                n.position.x += sin(n.position.y * 0.01) * deltaTime * 20
                n.position.y += cos(n.position.x * 0.01) * deltaTime * 10
                // Wrap around canvas
                if n.position.x < -200 { n.position.x = canvasWidth + 100 }
                if n.position.x > canvasWidth + 200 { n.position.x = -100 }
                if n.position.y < -200 { n.position.y = canvasHeight + 100 }
                if n.position.y > canvasHeight + 200 { n.position.y = -100 }
            }
        }

        // Panel transitions on energy shifts
        let energyDelta = abs(audioState.overallEnergy - lastTransitionEnergy)
        if energyDelta > 0.3 && panelNames.count > 4 {
            // Swap a random panel
            let slotIndex = Int.random(in: 0..<4)
            let newPanelIndex = Int.random(in: 0..<panelNames.count)
            sceneGraph.updateNode(id: "panel-\(slotIndex)") { n in
                n.targetOpacity = 0 // fade out, then swap and fade in
            }
            // In a real implementation, handle the fade-out-swap-fade-in with a timer
            lastTransitionEnergy = audioState.overallEnergy
        }

        // Beat pulse — scale icons briefly
        if audioState.isBeat {
            for node in sceneGraph.allNodes(ofType: .icon) {
                sceneGraph.updateNode(id: node.id) { n in
                    n.scale = 0.35 // pop up
                    n.targetScale = 0.3 // settle back
                }
            }
        }
    }
}
```

- [ ] **Step 6: Run tests — verify they pass**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Composition/ Tests/CompositionTests/
git commit -m "feat: scene graph and composition engine with zone-based layout"
```

---

## Task 8: Shader Pipeline — Pass 1 (Composition)

**Goal:** Metal compute shader that composites multiple textured panels and icons into the single canvas texture, reading from the scene graph.

**Files:**
- Create: `Sources/Shaders/Composition.metal`
- Create: `Sources/Display/ShaderPipeline.swift`
- Modify: `Sources/Display/MetalRenderer.swift` (integrate pipeline)

- [ ] **Step 1: Create composition compute shader**

Create `Sources/Shaders/Composition.metal`:

```metal
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Composite 4 panel textures into a 2x2 grid on the canvas
// Each panel is bound to texture slots 1-4 individually
kernel void compositePanels(
    texture2d<float, access::write> canvas [[texture(0)]],
    texture2d<float> panel0 [[texture(1)]],
    texture2d<float> panel1 [[texture(2)]],
    texture2d<float> panel2 [[texture(3)]],
    texture2d<float> panel3 [[texture(4)]],
    constant float4 &tintColor [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint canvasW = canvas.get_width();
    uint canvasH = canvas.get_height();
    constexpr sampler s(filter::linear);

    // Determine which quadrant (0-3)
    uint quadX = gid.x < canvasW / 2 ? 0 : 1;
    uint quadY = gid.y < canvasH / 2 ? 0 : 1;
    uint quadrant = quadY * 2 + quadX;

    // Local UV within quadrant
    float2 localUV = float2(
        float(gid.x % (canvasW / 2)) / float(canvasW / 2),
        float(gid.y % (canvasH / 2)) / float(canvasH / 2)
    );

    float4 color;
    switch (quadrant) {
        case 0: color = panel0.sample(s, localUV); break;
        case 1: color = panel1.sample(s, localUV); break;
        case 2: color = panel2.sample(s, localUV); break;
        default: color = panel3.sample(s, localUV); break;
    }
    color.rgb *= tintColor.rgb;
    canvas.write(color, gid);
}

struct IconInstance {
    float2 position;    // center in canvas coords
    float2 size;        // width, height in pixels
    float opacity;
    float rotation;     // radians
    float scale;
    float padding;
};

// Overlay icons onto the canvas using alpha blending
// Each icon shares a single atlas texture; instance data controls placement
kernel void compositeIcons(
    texture2d<float, access::read_write> canvas [[texture(0)]],
    texture2d<float> iconAtlas [[texture(1)]],
    const device IconInstance *icons [[buffer(0)]],
    constant uint &iconCount [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 pixelPos = float2(gid);
    float4 color = canvas.read(gid);
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    for (uint i = 0; i < iconCount && i < 32; i++) {
        IconInstance icon = icons[i];
        float2 scaledSize = icon.size * icon.scale;
        float2 localPos = pixelPos - icon.position;

        // Apply rotation
        float cosR = cos(icon.rotation);
        float sinR = sin(icon.rotation);
        float2 rotated = float2(
            localPos.x * cosR + localPos.y * sinR,
            -localPos.x * sinR + localPos.y * cosR
        );

        // Check if pixel is within icon bounds
        float2 halfSize = scaledSize * 0.5;
        if (abs(rotated.x) < halfSize.x && abs(rotated.y) < halfSize.y) {
            float2 uv = (rotated + halfSize) / scaledSize;
            float4 texColor = iconAtlas.sample(s, uv);
            texColor.a *= icon.opacity;
            color.rgb = mix(color.rgb, texColor.rgb, texColor.a);
        }
    }

    canvas.write(color, gid);
}
```

- [ ] **Step 2: Create ShaderPipeline**

Create `Sources/Display/ShaderPipeline.swift`:

```swift
import Foundation
import Metal

final class ShaderPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // Compute pipelines
    private var compositePanelsPipeline: MTLComputePipelineState!
    private var compositeIconsPipeline: MTLComputePipelineState!
    private var iconInstanceBuffer: MTLBuffer?

    // Render pipelines (for pass 2 effects)
    private var effectsPipeline: MTLRenderPipelineState?

    // Intermediate textures
    private(set) var compositionOutput: MTLTexture!

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
    }

    /// Pass 1a: Composite panels into the canvas (2x2 grid)
    func compositePanels(panelTextures: [MTLTexture],
                         tintColor: SIMD4<Float>,
                         commandBuffer: MTLCommandBuffer) {
        guard panelTextures.count >= 4 else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(compositePanelsPipeline)
        encoder.setTexture(compositionOutput, index: 0)

        // Bind each panel individually to texture slots 1-4
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

    /// Pass 1b: Overlay icons onto the canvas
    func compositeIcons(iconNodes: [SceneNode],
                        iconTexture: MTLTexture,
                        commandBuffer: MTLCommandBuffer) {
        guard !iconNodes.isEmpty else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(compositeIconsPipeline)
        encoder.setTexture(compositionOutput, index: 0)
        encoder.setTexture(iconTexture, index: 1)

        // Build instance buffer from scene nodes
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
                size: SIMD2(256, 256), // default icon size
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
```

- [ ] **Step 3: Integrate ShaderPipeline into MetalRenderer**

Add to `MetalRenderer`:

```swift
// Add property
private(set) var shaderPipeline: ShaderPipeline!

// In init, after setupCanvasTexture():
shaderPipeline = try ShaderPipeline(device: device, commandQueue: commandQueue,
                                      canvasWidth: canvasWidth, canvasHeight: canvasHeight)

// Add method to run the full render pipeline
func renderFrame(panelTextures: [MTLTexture], tintColor: SIMD4<Float>) {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

    // Pass 1: Composition
    shaderPipeline.compositePanels(panelTextures: panelTextures,
                                    tintColor: tintColor,
                                    commandBuffer: commandBuffer)

    // Copy composition output to canvas
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
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

Expected: Builds successfully. Shader compilation succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shaders/Composition.metal Sources/Display/ShaderPipeline.swift Sources/Display/MetalRenderer.swift
git commit -m "feat: composition shader pipeline (pass 1) with panel tiling"
```

---

## Task 9: Shader Pipeline — Pass 2 (Audio-Reactive Effects)

**Goal:** Fragment shaders that apply corruption-driven visual effects to the composed scene. Each effect is driven by audio bands and the corruption index.

**Files:**
- Create: `Sources/Shaders/Effects.metal`
- Modify: `Sources/Display/ShaderPipeline.swift` (add pass 2)

- [ ] **Step 1: Create effects fragment shader**

Create `Sources/Shaders/Effects.metal`:

```metal
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// --- Utility functions ---

float2 distort(float2 uv, float amount, float time) {
    float2 offset = float2(
        sin(uv.y * 20.0 + time * 2.0) * amount,
        cos(uv.x * 20.0 + time * 1.5) * amount
    );
    return uv + offset;
}

float crackPattern(float2 uv, float time, float intensity) {
    // Voronoi-based crack lines
    float2 p = uv * 8.0;
    float2 i_p = floor(p);
    float2 f_p = fract(p);

    float minDist = 1.0;
    float secondDist = 1.0;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(x, y);
            float2 cellPos = fract(sin(dot(i_p + neighbor, float2(127.1, 311.7))) * 43758.5453);
            cellPos = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * cellPos);
            float2 diff = neighbor + cellPos - f_p;
            float d = length(diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }

    float edge = secondDist - minDist;
    return smoothstep(0.0, 0.05 * intensity, edge);
}

// --- Main effects fragment shader ---

fragment float4 effectsFragment(
    VertexOut in [[stage_in]],
    texture2d<float> compositionTex [[texture(0)]],
    constant AudioUniforms &audio [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float corruption = audio.corruptionIndex;
    float time = audio.time;

    // --- Glass Refraction (driven by sub-bass) ---
    float refractionAmount = audio.bands[0] * corruption * 0.03;
    float2 refractedUV = distort(uv, refractionAmount, time);

    // --- Chromatic Aberration (driven by mids + corruption) ---
    float aberration = audio.bands[2] * corruption * 0.008;
    float4 colorR = compositionTex.sample(s, refractedUV + float2(aberration, 0));
    float4 colorG = compositionTex.sample(s, refractedUV);
    float4 colorB = compositionTex.sample(s, refractedUV - float2(aberration, 0));
    float4 color = float4(colorR.r, colorG.g, colorB.b, 1.0);

    // --- Lead Line Darkening (driven by bass) ---
    float leadIntensity = 1.0 + corruption * 0.5;
    float cracks = crackPattern(uv, time, leadIntensity);
    float leadDarken = mix(1.0, cracks, 0.3 + corruption * 0.4);
    color.rgb *= leadDarken;

    // --- Candlelight / Backlighting (driven by beat phase) ---
    float lightIntensity = mix(
        0.8 + 0.2 * sin(audio.beatPhase * 3.14159 * 2.0),  // gentle flicker
        0.5 + 0.5 * step(0.5, fract(audio.beatPhase * 2.0)), // harsh strobe
        corruption
    );
    // Beat pulse — bright flash on beat
    float beatFlash = audio.isBeat * (1.0 - corruption * 0.5) * 0.3;
    lightIntensity += beatFlash;
    color.rgb *= lightIntensity;

    // --- Color Grading (driven by corruption + highs) ---
    // Sacred: warm (blue/red/gold) → Profane: toxic (green/magenta/neon)
    float3 sacredTint = float3(1.0, 0.9, 0.7);   // warm
    float3 profaneTint = float3(0.7, 1.1, 0.9);   // sickly green shift
    float3 abyssTint = float3(1.2, 0.6, 1.3);     // neon magenta
    float3 tint;
    if (corruption < 0.6) {
        tint = mix(sacredTint, profaneTint, corruption / 0.6);
    } else {
        tint = mix(profaneTint, abyssTint, (corruption - 0.6) / 0.4);
    }
    // Highs add sparkle/shimmer to the tint
    tint += audio.bands[3] * 0.1;
    color.rgb *= tint;

    // --- Icon Distortion (driven by corruption index) ---
    // Geometry warping increases with corruption
    if (corruption > 0.4) {
        float warpStrength = (corruption - 0.4) * 0.05;
        float2 warpedUV = uv;
        warpedUV.x += sin(uv.y * 30.0 + time) * warpStrength;
        warpedUV.y += cos(uv.x * 25.0 + time * 0.8) * warpStrength;
        float4 warpedColor = compositionTex.sample(s, warpedUV);
        color = mix(color, warpedColor, (corruption - 0.4) / 0.6);
    }

    // --- Geometry Folding (full spectrum, high corruption) ---
    if (corruption > 0.7) {
        float foldStrength = (corruption - 0.7) / 0.3;
        float energy = (audio.bands[0] + audio.bands[1] + audio.bands[2] + audio.bands[3]) * 0.25;
        float2 foldedUV = uv;
        // Mirror fold
        if (foldStrength > 0.5) {
            foldedUV = abs(foldedUV * 2.0 - 1.0);
        }
        foldedUV += float2(sin(time * 1.5), cos(time * 1.2)) * foldStrength * energy * 0.1;
        float4 foldedColor = compositionTex.sample(s, foldedUV);
        color = mix(color, foldedColor, foldStrength * 0.5);
    }

    // --- Transient flash (drops/breakdowns) ---
    if (audio.isTransient > 0.5) {
        color.rgb = mix(color.rgb, float3(1.0), 0.4);
    }

    // --- Saturation push with corruption ---
    float3 gray = float3(dot(color.rgb, float3(0.299, 0.587, 0.114)));
    float saturation = 1.0 + corruption * 0.8; // oversaturate as corruption grows
    color.rgb = mix(gray, color.rgb, saturation);

    return color;
}
```

- [ ] **Step 2: Add effects pass to ShaderPipeline**

Add to `Sources/Display/ShaderPipeline.swift`:

```swift
// Add render pipeline for effects
private var effectsRenderPipeline: MTLRenderPipelineState!
private(set) var effectsOutput: MTLTexture!

// In setupPipelines(), add:
let effectsDesc = MTLRenderPipelineDescriptor()
effectsDesc.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
effectsDesc.fragmentFunction = library.makeFunction(name: "effectsFragment")
effectsDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
effectsRenderPipeline = try device.makeRenderPipelineState(descriptor: effectsDesc)

// In setupTextures(), add:
effectsOutput = device.makeTexture(descriptor: descriptor) // same descriptor

// Add method:
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
```

- [ ] **Step 3: Build and verify shaders compile**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

Expected: Build succeeds. No shader compilation errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shaders/Effects.metal Sources/Display/ShaderPipeline.swift
git commit -m "feat: audio-reactive effects shaders (pass 2) with corruption arc"
```

---

## Task 10: Shader Pipeline — Pass 3 (Post-Processing)

**Goal:** Bloom, film grain, vignette, and motion blur as the final polish pass.

**Files:**
- Create: `Sources/Shaders/PostProcess.metal`
- Modify: `Sources/Display/ShaderPipeline.swift` (add pass 3)

- [ ] **Step 1: Create post-processing shader**

Create `Sources/Shaders/PostProcess.metal`:

```metal
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Hash function for grain
float hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fragment float4 postProcessFragment(
    VertexOut in [[stage_in]],
    texture2d<float> effectsTex [[texture(0)]],
    texture2d<float> prevFrameTex [[texture(1)]],
    constant AudioUniforms &audio [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float4 color = effectsTex.sample(s, uv);
    float corruption = audio.corruptionIndex;

    // --- Bloom ---
    // Sample surrounding pixels for glow
    float bloomIntensity = 0.3 + audio.bands[1] * 0.4; // bass drives bloom
    float4 bloom = float4(0);
    float bloomRadius = 0.003 + corruption * 0.003;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            if (x == 0 && y == 0) continue;
            float2 offset = float2(x, y) * bloomRadius;
            bloom += effectsTex.sample(s, uv + offset);
        }
    }
    bloom /= 24.0;
    // Only bloom bright areas
    float brightness = dot(bloom.rgb, float3(0.299, 0.587, 0.114));
    bloom *= smoothstep(0.4, 0.8, brightness);
    color.rgb += bloom.rgb * bloomIntensity;

    // --- Film Grain ---
    float grain = hash(uv * float2(effectsTex.get_width(), effectsTex.get_height()) + audio.time * 100.0);
    grain = (grain - 0.5) * 0.06; // subtle
    color.rgb += grain;

    // --- Vignette ---
    float2 vignetteUV = uv * (1.0 - uv);
    float vignette = vignetteUV.x * vignetteUV.y * 15.0;
    vignette = pow(vignette, 0.3 + corruption * 0.2); // tighter vignette with corruption
    color.rgb *= vignette;

    // --- Motion Blur (blend with previous frame) ---
    float motionBlurAmount = 0.1 + corruption * 0.15;
    float4 prevColor = prevFrameTex.sample(s, uv);
    color = mix(color, prevColor, motionBlurAmount);

    // Clamp output
    color = clamp(color, 0.0, 1.0);
    color.a = 1.0;

    return color;
}
```

- [ ] **Step 2: Add post-processing pass to ShaderPipeline**

Add to `Sources/Display/ShaderPipeline.swift`:

```swift
// Add properties
private var postProcessPipeline: MTLRenderPipelineState!
private(set) var postProcessOutput: MTLTexture!
private var previousFrameTexture: MTLTexture!

// In setupPipelines(), add:
let postDesc = MTLRenderPipelineDescriptor()
postDesc.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
postDesc.fragmentFunction = library.makeFunction(name: "postProcessFragment")
postDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
postProcessPipeline = try device.makeRenderPipelineState(descriptor: postDesc)

// In setupTextures(), add:
postProcessOutput = device.makeTexture(descriptor: descriptor)
previousFrameTexture = device.makeTexture(descriptor: descriptor)

// Add method:
func applyPostProcessing(audioUniforms: AudioUniforms, commandBuffer: MTLCommandBuffer) {
    let passDescriptor = MTLRenderPassDescriptor()
    passDescriptor.colorAttachments[0].texture = postProcessOutput
    passDescriptor.colorAttachments[0].loadAction = .dontCare
    passDescriptor.colorAttachments[0].storeAction = .store

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
    encoder.setRenderPipelineState(postProcessPipeline)
    encoder.setFragmentTexture(effectsOutput, index: 0)
    encoder.setFragmentTexture(previousFrameTexture, index: 1)
    var uniforms = audioUniforms
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AudioUniforms>.size, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()

    // Copy current output to previous frame for next iteration
    guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
    blitEncoder.copy(from: postProcessOutput, to: previousFrameTexture)
    blitEncoder.endEncoding()
}

/// The final output texture after all passes
var finalOutput: MTLTexture {
    postProcessOutput
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Shaders/PostProcess.metal Sources/Display/ShaderPipeline.swift
git commit -m "feat: post-processing shaders (pass 3) with bloom, grain, vignette"
```

---

## Task 11: Display Manager (Single + Multi-Display)

**Goal:** Manage fullscreen windows on multiple displays, blit canvas quadrants to each.

**Files:**
- Create: `Sources/Display/GridConfig.swift`
- Create: `Sources/Display/DisplayManager.swift`
- Create: `Resources/grid-config.json`

- [ ] **Step 1: Create grid config**

Create `Sources/Display/GridConfig.swift`:

```swift
import Foundation

struct GridConfig: Codable {
    let columns: Int
    let rows: Int
    let displays: [DisplaySlot]

    struct DisplaySlot: Codable {
        let column: Int
        let row: Int
        let displayID: UInt32? // CGDirectDisplayID, nil = auto-assign
    }

    static let defaultConfig = GridConfig(
        columns: 2, rows: 2,
        displays: [
            DisplaySlot(column: 0, row: 0, displayID: nil),
            DisplaySlot(column: 1, row: 0, displayID: nil),
            DisplaySlot(column: 0, row: 1, displayID: nil),
            DisplaySlot(column: 1, row: 1, displayID: nil),
        ]
    )

    static func load(from url: URL) throws -> GridConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GridConfig.self, from: data)
    }
}
```

Create `Resources/grid-config.json`:

```json
{
    "columns": 2,
    "rows": 2,
    "displays": [
        { "column": 0, "row": 0 },
        { "column": 1, "row": 0 },
        { "column": 0, "row": 1 },
        { "column": 1, "row": 1 }
    ]
}
```

- [ ] **Step 2: Create DisplayManager**

Create `Sources/Display/DisplayManager.swift`:

```swift
import Cocoa
import Metal
import QuartzCore

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

    /// Set up windows on available displays
    func setup() {
        let screens = NSScreen.screens

        if screens.count < gridConfig.columns * gridConfig.rows {
            // Not enough displays — use single display mode
            setupSingleDisplay(screen: screens[0])
            singleDisplayMode = true
        } else {
            setupMultiDisplay(screens: screens)
            singleDisplayMode = false
        }
    }

    private func setupSingleDisplay(screen: NSScreen) {
        let window = createFullscreenWindow(on: screen)
        let layer = createMetalLayer(size: screen.frame.size, scale: screen.backingScaleFactor)
        window.contentView!.layer = layer
        window.contentView!.wantsLayer = true
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        metalLayers.append(layer)
    }

    private func setupMultiDisplay(screens: [NSScreen]) {
        // Skip the main screen (index 0 is typically the primary/menu bar screen)
        // Assign external screens to grid slots
        let externalScreens = screens.count > 1 ? Array(screens[1...]) : screens

        for (i, slot) in gridConfig.displays.enumerated() {
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

    /// Blit the appropriate region of the canvas to each display
    func present() {
        if singleDisplayMode {
            // Single display: show the whole canvas scaled
            renderer.presentCanvas(to: metalLayers[0])
        } else {
            // Multi display: blit quadrants
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
```

- [ ] **Step 3: Add region blit method to MetalRenderer**

Add to `Sources/Display/MetalRenderer.swift`:

```swift
/// Present a sub-region of the canvas to a metal layer (for multi-display)
/// Uses blit encoder to copy the exact quadrant, then passthrough renders it.
func presentCanvasRegion(to layer: CAMetalLayer, region: MTLRegion) {
    guard let drawable = layer.nextDrawable() else { return }
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

    // Create a temporary texture sized to the quadrant
    let quadDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: region.size.width, height: region.size.height,
        mipmapped: false
    )
    quadDesc.usage = [.shaderRead, .renderTarget]
    quadDesc.storageMode = .private
    guard let quadTexture = device.makeTexture(descriptor: quadDesc) else { return }

    // Blit the region from canvas to the quadrant texture
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

    // Render the quadrant texture to the drawable
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
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Display/DisplayManager.swift Sources/Display/GridConfig.swift Resources/grid-config.json Sources/Display/MetalRenderer.swift
git commit -m "feat: display manager with single and multi-display support"
```

---

## Task 12: Debug Overlay

**Goal:** HUD showing FPS, audio band levels, BPM, corruption index and phase.

**Files:**
- Create: `Sources/Debug/DebugOverlay.swift`

- [ ] **Step 1: Implement debug overlay**

Create `Sources/Debug/DebugOverlay.swift`:

```swift
import Cocoa
import Metal

final class DebugOverlay {
    private var isVisible = true
    private var frameCount = 0
    private var lastFPSTime: Double = 0
    private var currentFPS: Int = 0
    private let overlayView: NSTextField

    init(parentView: NSView) {
        overlayView = NSTextField(frame: NSRect(x: 10, y: 10, width: 400, height: 200))
        overlayView.isEditable = false
        overlayView.isBordered = false
        overlayView.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        overlayView.textColor = .green
        overlayView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        overlayView.isHidden = !isVisible
        parentView.addSubview(overlayView)
    }

    func toggle() {
        isVisible.toggle()
        overlayView.isHidden = !isVisible
    }

    func update(audioState: AudioState, time: Double) {
        guard isVisible else { return }

        frameCount += 1
        if time - lastFPSTime >= 1.0 {
            currentFPS = frameCount
            frameCount = 0
            lastFPSTime = time
        }

        let phase = CorruptionPhase.from(index: audioState.corruptionIndex)
        let barLength = 20

        func bar(_ value: Float) -> String {
            let filled = Int(value * Float(barLength))
            return String(repeating: "█", count: filled) + String(repeating: "░", count: barLength - filled)
        }

        let text = """
        SANCTUM DEBUG
        FPS: \(currentFPS)
        ─────────────────────────
        SUB-BASS [\(bar(audioState.subBass))] \(String(format: "%.2f", audioState.subBass))
        BASS     [\(bar(audioState.bass))] \(String(format: "%.2f", audioState.bass))
        MIDS     [\(bar(audioState.mids))] \(String(format: "%.2f", audioState.mids))
        HIGHS    [\(bar(audioState.highs))] \(String(format: "%.2f", audioState.highs))
        ─────────────────────────
        BPM: \(String(format: "%.0f", audioState.bpm))  BEAT: \(audioState.isBeat ? "●" : "○")
        CORRUPTION: [\(bar(audioState.corruptionIndex))] \(String(format: "%.3f", audioState.corruptionIndex))
        PHASE: \(phase.rawValue.uppercased())
        """

        overlayView.stringValue = text
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Debug/DebugOverlay.swift
git commit -m "feat: debug overlay with FPS, audio bands, and corruption status"
```

---

## Task 13: App Integration (Wire Everything Together)

**Goal:** Connect all modules into the main render loop: audio → analysis → corruption → composition → shaders → display.

**Files:**
- Create: `Sources/App/Config.swift`
- Modify: `Sources/App/AppDelegate.swift` (full integration)
- Modify: `Sources/Audio/AnalysisEngine.swift` (wire corruption)

- [ ] **Step 1: Create Config**

Create `Sources/App/Config.swift`:

```swift
import Foundation

struct SanctumConfig: Codable {
    var canvasWidth: Int = 3840
    var canvasHeight: Int = 2160
    var targetFPS: Int = 60
    var corruptionWindowHours: Double = 5.0
    var audioBufferSize: Int = 4096
    var debugOverlay: Bool = true

    static func load() -> SanctumConfig {
        let configURL = Bundle.main.url(forResource: "sanctum-config", withExtension: "json")
            ?? URL(fileURLWithPath: "sanctum-config.json")

        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(SanctumConfig.self, from: data) else {
            return SanctumConfig()
        }
        return config
    }
}
```

- [ ] **Step 2: Rewrite AppDelegate with full integration**

Update `Sources/App/AppDelegate.swift` to wire all modules:

```swift
import Cocoa
import Metal
import QuartzCore

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
    private var displayLink: CVDisplayLink?
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
            try audioCapture.start()
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
            for i in 0..<4 {
                let colors: [(UInt8, UInt8, UInt8, UInt8)] = [
                    (15, 10, 60, 255),   // deep blue
                    (140, 20, 30, 255),  // ruby red
                    (80, 10, 80, 255),   // deep purple
                    (20, 60, 30, 255),   // forest green
                ]
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
            DispatchQueue.main.async { delegate.renderFrame() }
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
        // Gather panel textures from asset library via composition engine
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
```

- [ ] **Step 3: Build the full integrated app**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

Expected: Build succeeds. Running the app opens a window with audio-reactive visuals (placeholder colors with effects applied).

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Config.swift Sources/App/AppDelegate.swift
git commit -m "feat: full module integration — audio to visuals render loop"
```

---

## Task 14: Audio File Input for Development

**Goal:** Support loading a WAV/AIFF file as audio source instead of live line-in, for deterministic development and testing.

**Files:**
- Modify: `Sources/Audio/AudioCapture.swift` (add file playback mode)
- Modify: `Sources/App/Config.swift` (add audio source option)

- [ ] **Step 1: Add file-based audio source to AudioCapture**

Add to `Sources/Audio/AudioCapture.swift`:

```swift
/// Load audio from a file and feed it into the ring buffer in real-time
func startFromFile(url: URL, loop: Bool = true) throws {
    guard let audioFile = try? AVAudioFile(forReading: url) else {
        throw SanctumError.assetLoadFailed(url.path)
    }

    let format = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw SanctumError.assetLoadFailed("Could not create buffer")
    }
    try audioFile.read(into: buffer)

    // Convert to mono float samples
    guard let floatData = buffer.floatChannelData else {
        throw SanctumError.assetLoadFailed("Not float format")
    }
    let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))

    // Feed samples on a timer matching the sample rate
    let samplesPerFrame = Int(format.sampleRate / 60.0) // ~60fps chunks
    var offset = 0

    Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
        guard let self else { timer.invalidate(); return }
        let end = min(offset + samplesPerFrame, samples.count)
        let chunk = Array(samples[offset..<end])
        chunk.withUnsafeBufferPointer { ptr in
            self.writeSamples(ptr)
        }
        offset = end
        if offset >= samples.count {
            if loop {
                offset = 0
            } else {
                timer.invalidate()
            }
        }
    }
}
```

- [ ] **Step 2: Add config option for audio source**

Add to `SanctumConfig`:

```swift
var audioSource: String = "line-in" // "line-in" or path to WAV/AIFF file
```

Update `AppDelegate.applicationDidFinishLaunching` audio setup:

```swift
if config.audioSource == "line-in" {
    try audioCapture.start()
} else {
    let fileURL = URL(fileURLWithPath: config.audioSource)
    try audioCapture.startFromFile(url: fileURL, loop: true)
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Debug build
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Audio/AudioCapture.swift Sources/App/Config.swift Sources/App/AppDelegate.swift
git commit -m "feat: audio file input for development and testing"
```

---

## Task 15: Final — Run All Tests and Push

**Goal:** Ensure everything builds and tests pass. Push to GitHub.

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test -project Sanctum.xcodeproj -scheme SanctumTests -configuration Debug
```

Expected: All tests pass.

- [ ] **Step 2: Build release**

```bash
xcodebuild -project Sanctum.xcodeproj -scheme Sanctum -configuration Release build
```

Expected: Release build succeeds.

- [ ] **Step 3: Push to GitHub**

```bash
git push origin main
```

- [ ] **Step 4: Tag initial version**

```bash
git tag v0.1.0
git push origin v0.1.0
```
