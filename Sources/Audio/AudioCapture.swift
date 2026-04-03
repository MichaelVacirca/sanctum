import Foundation
import AudioToolbox
import CoreAudio
import AVFoundation

final class AudioCapture: @unchecked Sendable {
    fileprivate var audioUnit: AudioComponentInstance?
    private let bufferSize: Int
    private var ringBuffer: [Float]
    private var writeIndex: Int = 0
    private let lock = NSLock()
    let sampleRate: Double

    var onSamplesAvailable: (([Float]) -> Void)?

    init(bufferSize: Int = 4096, preferredSampleRate: Double = 48000) {
        self.bufferSize = bufferSize
        self.sampleRate = preferredSampleRate
        self.ringBuffer = [Float](repeating: 0, count: bufferSize * 4)
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

        guard let floatData = buffer.floatChannelData else {
            throw SanctumError.assetLoadFailed("Not float format")
        }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))

        let samplesPerFrame = Int(format.sampleRate / 60.0)
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

    func stop() {
        guard let au = audioUnit else { return }
        AudioOutputUnitStop(au)
        AudioComponentInstanceDispose(au)
        audioUnit = nil
    }

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
