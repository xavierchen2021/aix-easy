import AppKit
import AVFoundation

/// macOS TTS 语音播放服务（支持系统 AVSpeechSynthesizer 和 Edge TTS 双引擎）
@MainActor
class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()
    
    @Published var isSpeaking = false
    @Published var currentSpeakingId: String = ""
    @Published var isLoading = false
    
    // 系统 TTS
    private let synthesizer = AVSpeechSynthesizer()
    private var delegate: TTSSpeechDelegate?
    
    // Edge TTS（AVAudioPlayer 播放 MP3）
    private var audioPlayer: AVAudioPlayer?
    private var edgeTask: URLSessionDataTask?
    
    private static let edgeTtsBaseUrl = "http://127.0.0.1:9881"
    
    private override init() {
        super.init()
        delegate = TTSSpeechDelegate { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
                self?.currentSpeakingId = ""
            }
        }
        synthesizer.delegate = delegate
    }
    
    /// 朗读文本（根据配置自动选择引擎）
    func speak(_ text: String, language: TTSLanguage = .auto, id: String = "") {
        stop()
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        currentSpeakingId = id
        isSpeaking = true
        
        let config = FloatingButtonConfigManager.shared.config
        if config.ttsMode == .edge {
            isLoading = true
            speakWithEdgeTTS(trimmed, language: language)
        } else {
            speakWithSystem(trimmed, language: language)
        }
    }
    
    /// 停止朗读
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        edgeTask?.cancel()
        edgeTask = nil
        isSpeaking = false
        isLoading = false
        currentSpeakingId = ""
    }
    
    /// 切换播放/停止
    func toggle(_ text: String, language: TTSLanguage = .auto, id: String = "") {
        if isSpeaking && currentSpeakingId == id {
            stop()
        } else {
            speak(text, language: language, id: id)
        }
    }
    
    // MARK: - 系统 TTS
    
    private func speakWithSystem(_ text: String, language: TTSLanguage) {
        let langCode = resolveLangCode(text, language: language)
        
        let utterance = AVSpeechUtterance(string: text)
        let config = FloatingButtonConfigManager.shared.config
        let savedVoiceId = langCode.hasPrefix("en") ? config.ttsEnglishVoice : config.ttsChineseVoice
        if !savedVoiceId.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: savedVoiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: langCode)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
    
    // MARK: - Edge TTS
    
    private func speakWithEdgeTTS(_ text: String, language: TTSLanguage) {
        let langCode = resolveLangCode(text, language: language)
        let config = FloatingButtonConfigManager.shared.config
        let voice = langCode.hasPrefix("en") ? config.edgeTtsEnglishVoice : config.edgeTtsChineseVoice
        
        // 先查缓存
        if let cachedData = TTSCacheManager.shared.lookup(text: text, voice: voice) {
            print("[TTSService] 缓存命中: \(text.prefix(30))...")
            isLoading = false
            playAudioData(cachedData, text: text, language: language)
            return
        }
        
        print("[TTSService] 缓存未命中，请求 API: \(text.prefix(30))...")
        
        guard let url = URL(string: "\(Self.edgeTtsBaseUrl)/tts") else {
            fallbackToSystem(text, language: language)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let body: [String: String] = [
            "text": text,
            "voice": voice,
            "rate": "+0%",
            "volume": "+0%"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let speakingId = currentSpeakingId
        edgeTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self = self, self.currentSpeakingId == speakingId else { return }
                
                if let error = error {
                    print("[TTSService] Edge TTS 请求失败: \(error.localizedDescription)，回退系统 TTS")
                    self.isLoading = false
                    self.fallbackToSystem(text, language: language)
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let success = json["success"] as? Bool, success,
                      let audioBase64 = json["audioBase64"] as? String,
                      let audioData = Data(base64Encoded: audioBase64) else {
                    print("[TTSService] Edge TTS 响应解析失败，回退系统 TTS")
                    self.isLoading = false
                    self.fallbackToSystem(text, language: language)
                    return
                }
                
                self.isLoading = false
                
                // 存入缓存
                TTSCacheManager.shared.store(text: text, voice: voice, audioData: audioData)
                
                self.playAudioData(audioData, text: text, language: language)
            }
        }
        edgeTask?.resume()
    }
    
    /// 播放音频数据
    private func playAudioData(_ audioData: Data, text: String, language: TTSLanguage) {
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = audioPlayerDelegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("[TTSService] 音频播放失败: \(error.localizedDescription)，回退系统 TTS")
            fallbackToSystem(text, language: language)
        }
    }
    
    /// 直接播放音频 Data（供缓存管理等外部调用）
    func playRawAudio(_ audioData: Data, id: String = "") {
        stop()
        currentSpeakingId = id
        isSpeaking = true
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = audioPlayerDelegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("[TTSService] 音频播放失败: \(error.localizedDescription)")
            isSpeaking = false
            currentSpeakingId = ""
        }
    }
    
    private func fallbackToSystem(_ text: String, language: TTSLanguage) {
        speakWithSystem(text, language: language)
    }
    
    /// 检查 Edge TTS 服务是否可用
    static func checkEdgeTTSAvailable(completion: @escaping @Sendable (Bool) -> Void) {
        guard let url = URL(string: "\(edgeTtsBaseUrl)/health") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
    
    // MARK: - Edge TTS 语音列表
    
    struct EdgeVoiceInfo: Identifiable, Decodable {
        let name: String
        let friendlyName: String?
        let gender: String?
        let locale: String?
        
        var id: String { name }
        var displayName: String {
            if let friendly = friendlyName {
                return friendly
            }
            return name
        }
    }
    
    /// 从 Edge TTS 服务获取指定语言的语音列表
    static func fetchEdgeVoices(language: String, completion: @escaping @Sendable ([EdgeVoiceInfo]) -> Void) {
        guard let url = URL(string: "\(edgeTtsBaseUrl)/voices?language=\(language)") else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            // 响应格式：{ voices: [ { name, friendlyName, gender, locale }, ... ] }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let voicesArray = json["voices"] as? [[String: Any]] {
                let voices = voicesArray.compactMap { dict -> EdgeVoiceInfo? in
                    guard let name = dict["name"] as? String else { return nil }
                    return EdgeVoiceInfo(
                        name: name,
                        friendlyName: dict["friendlyName"] as? String,
                        gender: dict["gender"] as? String,
                        locale: dict["locale"] as? String
                    )
                }
                DispatchQueue.main.async { completion(voices) }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    // MARK: - AVAudioPlayer Delegate
    
    private lazy var audioPlayerDelegate: AudioPlayerDelegate = {
        AudioPlayerDelegate { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
                self?.currentSpeakingId = ""
            }
        }
    }()
    
    // MARK: - 语言枚举
    
    enum TTSLanguage {
        case auto    // 自动识别
        case english // 固定英语
        case chinese // 固定中文
    }
    
    // MARK: - 系统语音查询
    
    struct VoiceInfo: Identifiable {
        let id: String // identifier
        let name: String
        let language: String
    }
    
    /// 获取指定语言的可用系统语音列表
    static func availableVoices(for languagePrefix: String) -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languagePrefix) }
            .map { VoiceInfo(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted { $0.name < $1.name }
    }
    
    // MARK: - 内部工具
    
    private func resolveLangCode(_ text: String, language: TTSLanguage) -> String {
        switch language {
        case .english: return "en-US"
        case .chinese: return "zh-CN"
        case .auto: return detectLanguage(text) == "zh" ? "zh-CN" : "en-US"
        }
    }
    
    private func detectLanguage(_ text: String) -> String {
        for char in text {
            if char >= "\u{4e00}" && char <= "\u{9fff}" {
                return "zh"
            }
        }
        return "en"
    }
}

// MARK: - AVSpeechSynthesizer Delegate

private class TTSSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void
    
    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}

// MARK: - AVAudioPlayer Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void
    
    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish()
    }
}

// MARK: - 通用 TTS 播放按钮

import SwiftUI

struct TTSSpeakButton: View {
    let text: String
    var language: TTSService.TTSLanguage = .auto
    
    @StateObject private var ttsService = TTSService.shared
    @State private var buttonId = UUID().uuidString
    
    private var isThisPlaying: Bool {
        ttsService.isSpeaking && ttsService.currentSpeakingId == buttonId
    }
    
    private var isThisLoading: Bool {
        ttsService.isLoading && ttsService.currentSpeakingId == buttonId
    }
    
    var body: some View {
        Button(action: {
            ttsService.toggle(text, language: language, id: buttonId)
        }) {
            if isThisLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: isThisPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundColor(isThisPlaying ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(isThisLoading ? "加载中..." : "朗读")
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
