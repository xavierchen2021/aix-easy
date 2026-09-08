import Foundation
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreAudio

final class AudioActivityMonitor: NSObject, SCStreamOutput, @unchecked Sendable {
    static let shared = AudioActivityMonitor()

    private let stateQueue = DispatchQueue(label: "audio.activity.state")
    private let streamQueue = DispatchQueue(label: "audio.activity.stream")
    private let peakThreshold: Float = 0.01

    private var stream: SCStream?
    private var isCapturing: Bool = false
    private var lastPeak: Float = 0
    private var lastPeakTime: Date?
    private var hasSamples: Bool = false

    private override init() {}

    func startMonitoring() {
        let screenPermission = ScreenRecordingPermission.hasPermission()
        ReminderLogger.shared.logInfo("🎧 屏幕录制权限检测: \(screenPermission)")
        if !screenPermission {
            ReminderLogger.shared.logInfo("🎧 缺少屏幕录制权限，无法启动音频捕获")
            ScreenRecordingPermission.requestPermission()
            stateQueue.sync {
                isCapturing = false
            }
            return
        }

        let shouldStart = stateQueue.sync { () -> Bool in
            if isCapturing {
                return false
            }
            isCapturing = true
            lastPeak = 0
            lastPeakTime = nil
            hasSamples = false
            return true
        }

        guard shouldStart else { return }
        ReminderLogger.shared.logInfo("🎧 音频捕获启动中")

        Task { [weak self] in
            await self?.startCapture()
        }
    }

    func stopMonitoring() {
        let streamToStop = stateQueue.sync { () -> SCStream? in
            let current = stream
            stream = nil
            isCapturing = false
            lastPeak = 0
            lastPeakTime = nil
            hasSamples = false
            return current
        }

        guard let streamToStop = streamToStop else { return }
        ReminderLogger.shared.logInfo("🎧 音频捕获停止中")

        Task { [weak self] in
            await self?.stopCapture(streamToStop)
        }
    }

    func isOutputLoud() -> Bool {
        let snapshot = stateQueue.sync { () -> (Float, Date?) in
            (lastPeak, lastPeakTime)
        }

        guard let lastTime = snapshot.1 else { return false }
        guard Date().timeIntervalSince(lastTime) <= 1.5 else { return false }
        return snapshot.0 >= peakThreshold
    }

    func hasAudioSamples() -> Bool {
        stateQueue.sync { hasSamples }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        let peak = computePeak(from: sampleBuffer)
        guard peak > 0 else { return }

        stateQueue.async { [weak self] in
            self?.lastPeak = peak
            self?.lastPeakTime = Date()
            self?.hasSamples = true
        }
    }

    private func startCapture() async {
        do {
            if !ScreenRecordingPermission.hasPermission() {
                ReminderLogger.shared.logInfo("🎧 屏幕录制权限未授权，终止音频捕获启动")
                stateQueue.sync {
                    isCapturing = false
                }
                return
            }

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                stateQueue.async { [weak self] in
                    self?.isCapturing = false
                }
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
            config.width = display.width
            config.height = display.height

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: SCStreamOutputType.audio, sampleHandlerQueue: streamQueue)
            try await startStream(stream)

            ReminderLogger.shared.logInfo("🎧 音频捕获启动成功")

            stateQueue.sync {
                self.stream = stream
            }
        } catch {
            ReminderLogger.shared.logInfo("音频捕获启动失败: \(error.localizedDescription)")
            stateQueue.async { [weak self] in
                self?.isCapturing = false
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async {
        do {
            _ = try stream.removeStreamOutput(self, type: SCStreamOutputType.audio)
            try await stopStream(stream)
        } catch {
            ReminderLogger.shared.logInfo("音频捕获停止失败: \(error.localizedDescription)")
        }
    }

    private func startStream(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func stopStream(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func computePeak(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return 0 }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return 0 }

        var blockBuffer: CMBlockBuffer?
        var bufferListSize = 0
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return 0 }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status2 = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status2 == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let bits = Int(asbd.pointee.mBitsPerChannel)

        var peak: Float = 0
        for buffer in bufferList {
            guard let data = buffer.mData else { continue }

            if isFloat && bits == 32 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
                let samples = data.assumingMemoryBound(to: Float32.self)
                for i in 0..<count {
                    let value = abs(samples[i])
                    if value > peak { peak = value }
                }
            } else if isSignedInt && bits == 16 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = data.assumingMemoryBound(to: Int16.self)
                let scale = Float(Int16.max)
                for i in 0..<count {
                    let value = abs(Float(samples[i]) / scale)
                    if value > peak { peak = value }
                }
            }
        }

        return peak
    }
}
