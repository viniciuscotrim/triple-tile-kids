import AVFoundation
import UIKit

enum SoundKind { case tap, match, win }

/// Sintetizador de tons curtos (sem assets de áudio). Match = arpejo de 3 notas
/// ascendente, vitória = 5 notas, tap = nota única. Categoria .ambient respeita o
/// botão de silêncio e mixa com outros áudios.
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double = 44100
    private var ready = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            player.play()
            ready = true
        } catch {
            ready = false
        }
    }

    func play(_ kind: SoundKind) {
        guard ready else { return }
        let freqs: [Double]
        let noteDur: Double
        switch kind {
        case .tap:   freqs = [440];                          noteDur = 0.16
        case .match: freqs = [523, 784, 1047];               noteDur = 0.12
        case .win:   freqs = [523, 659, 784, 1047, 1319];    noteDur = 0.13
        }
        for f in freqs {
            if let buf = makeTone(freq: f, dur: noteDur) {
                player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            }
        }
    }

    private func makeTone(freq: Double, dur: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * dur)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buf.floatChannelData else { return nil }
        buf.frameLength = frames
        let twoPiF = 2.0 * Double.pi * freq
        let n = Int(frames)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            // Ataque rápido + decaimento exponencial → soa como xilofone/sino.
            let attack = min(1.0, t / 0.006)
            let decay = exp(-3.2 * t / dur)
            ch[0][i] = Float(sin(twoPiF * t) * 0.17 * attack * decay)
        }
        return buf
    }
}

/// Feedback tátil. Toque leve ao pegar tile; sucesso ao completar trio.
/// Silêncio ao bloquear é intencional (a ausência é o feedback de "não pode").
enum Haptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }
}
