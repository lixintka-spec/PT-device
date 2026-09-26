import AVFoundation
import CoreHaptics
import QuartzCore

/// Eyes-free coaching. The phone sits behind the knee, so the patient can't see it:
/// a tone that rises with the bend, parking-sensor ticks near the target, a buzz for
/// "perfect, hold", and a short voice. Every haptic is mirrored with sound (the Simulator
/// has no haptics) and the UI mirrors both visually.
@MainActor
final class FeedbackCoordinator {
    private let audio = ToneSynth()
    private let haptics = Haptics()
    private let speech = AVSpeechSynthesizer()
    private var lastTickTime: CFTimeInterval = 0
    var isMuted = false
    /// Increments on every tick so the UI can pulse in sync.
    private(set) var tickCount = 0
    var onTickPulse: (() -> Void)?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        audio.start()
        haptics.prepare()
    }

    /// Continuous tone mapped to the angle (only while exercising).
    func setTone(active: Bool, flexion: Double) {
        audio.setTone(frequency: 196 + flexion * 3.1, amplitude: (active && !isMuted) ? 0.045 : 0)
    }

    /// Parking-sensor ticks: the closer to the target, the faster.
    func proximity(flexion: Double, target: Double) {
        let distance = target - flexion
        guard distance > 0.8, distance < 16 else { return }
        let interval = 0.07 + (distance / 16) * 0.55
        let now = CACurrentMediaTime()
        guard now - lastTickTime >= interval else { return }
        lastTickTime = now
        tick(intensity: Float(1 - distance / 16))
    }

    func tick(intensity: Float = 0.6) {
        tickCount += 1
        onTickPulse?()
        if !isMuted { audio.playTick() }
        haptics.transient(intensity: 0.4 + intensity * 0.6)
    }

    func perfect() {
        if !isMuted { audio.playBuzz() }
        haptics.buzz()
    }

    func success() {
        if !isMuted { audio.playChime() }
        haptics.transient(intensity: 1)
    }

    func warning() {
        if !isMuted { audio.playWarning() }
        haptics.transient(intensity: 0.8)
    }

    func say(_ text: String) {
        guard !isMuted else { return }
        speech.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.05
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speech.speak(utterance)
    }
}

/// Minimal synth: one continuous sine voice plus pre-rendered one-shots.
final class ToneSynth: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let tickPlayer = AVAudioPlayerNode()
    private let fxPlayer = AVAudioPlayerNode()
    private var source: AVAudioSourceNode!
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    // Shared with the render thread; benign races on Double are acceptable for a tone.
    private var frequency: Double = 300
    private var targetAmp: Double = 0
    private var amp: Double = 0
    private var phase: Double = 0
    private var currentFreq: Double = 300

    private lazy var tickBuffer = render(duration: 0.035) { t in sin(2 * .pi * 1850 * t) * exp(-t * 90) * 0.55 }
    private lazy var buzzBuffer = render(duration: 0.5) { t in
        let saw = 2 * ((t * 150).truncatingRemainder(dividingBy: 1)) - 1
        let env = min(1, t * 60) * exp(-t * 3.2)
        return (saw * 0.45 + sin(2 * .pi * 300 * t) * 0.25) * env
    }
    private lazy var chimeBuffer = render(duration: 0.9) { t in
        let a = sin(2 * .pi * 880 * t) * exp(-t * 5)
        let b = t > 0.14 ? sin(2 * .pi * 1318.5 * (t - 0.14)) * exp(-(t - 0.14) * 4) : 0
        return (a + b) * 0.32
    }
    private lazy var warningBuffer = render(duration: 0.32) { t in
        let f = t < 0.16 ? 520.0 : 390.0
        return sin(2 * .pi * f * t) * 0.3 * (t < 0.16 ? exp(-t * 12) : exp(-(t - 0.16) * 12))
    }

    func start() {
        source = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let sr = 44_100.0
            for frame in 0..<Int(frameCount) {
                self.currentFreq += (self.frequency - self.currentFreq) * 0.0015
                self.amp += (self.targetAmp - self.amp) * 0.0008
                self.phase += 2 * .pi * self.currentFreq / sr
                if self.phase > 2 * .pi { self.phase -= 2 * .pi }
                let sample = Float((sin(self.phase) * 0.8 + sin(2 * self.phase) * 0.2) * self.amp)
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.attach(tickPlayer)
        engine.attach(fxPlayer)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.connect(tickPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(fxPlayer, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            tickPlayer.play()
            fxPlayer.play()
        } catch {
            print("Range audio failed to start: \(error)")
        }
    }

    func setTone(frequency: Double, amplitude: Double) {
        self.frequency = frequency
        self.targetAmp = amplitude
    }

    func playTick() { tickPlayer.scheduleBuffer(tickBuffer, at: nil, options: [], completionHandler: nil) }
    func playBuzz() { fxPlayer.scheduleBuffer(buzzBuffer, at: nil, options: [.interrupts], completionHandler: nil) }
    func playChime() { fxPlayer.scheduleBuffer(chimeBuffer, at: nil, options: [.interrupts], completionHandler: nil) }
    func playWarning() { fxPlayer.scheduleBuffer(warningBuffer, at: nil, options: [.interrupts], completionHandler: nil) }

    private func render(duration: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = Float(f(Double(i) / 44_100)) }
        return buffer
    }
}

/// Core Haptics wrapper; silently no-ops where haptics aren't supported (Simulator).
final class Haptics {
    private var engine: CHHapticEngine?

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        try? engine?.start()
    }

    func transient(intensity: Float) {
        play([CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
        ], relativeTime: 0)])
    }

    func buzz() {
        play([CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
        ], relativeTime: 0, duration: 0.45)])
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: 0)
        } catch {
            try? engine.start()
        }
    }
}
