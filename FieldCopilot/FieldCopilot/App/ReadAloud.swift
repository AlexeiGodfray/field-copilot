import AVFoundation
import CoreML
import KokoroTTS
import Observation

/// Reads a scan's results aloud, for when hands and eyes are busy. Uses Kokoro, an open voice model that
/// runs on the phone, or the phone's own voice if the model wasn't fetched before the app was built.
@Observable
final class ReadAloud: NSObject, AVSpeechSynthesizerDelegate {
    /// True from the tap until the last word, including while the voice model loads.
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var reading: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ scan: Scan) {
        stop()
        // Spoken audio through the speaker, with music and podcasts turned down meanwhile.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)
        isSpeaking = true
        let sentences = scan.spokenSentences
        guard NaturalVoice.isBundled else { return speakWithPhoneVoice(sentences) }
        reading = Task { await speakNaturally(sentences) }
    }

    func stop() {
        reading?.cancel()
        reading = nil
        player.stop()
        engine.stop()
        synthesizer.stopSpeaking(at: .immediate)
        finished()
    }

    /// Each sentence is generated while the one before it plays.
    private func speakNaturally(_ sentences: [String]) async {
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: Double(NaturalVoice.sampleRate), channels: 1)!
            if player.engine == nil {
                engine.attach(player)
                try engine.connectNode(player, to: engine.mainMixerNode, format: format)
            }
            for sentence in sentences {
                let samples = try await NaturalVoice.shared.audio(for: sentence)
                try Task.checkCancellation()
                try queue(samples, format)
            }
            // Buffers play in order, so this one finishing means everything has been said.
            await player.scheduleBuffer(Self.buffer([0], format), completionCallbackType: .dataPlayedBack)
            guard !Task.isCancelled else { return }
            stop()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            speakWithPhoneVoice(sentences)
        }
    }

    /// Adds a sentence after the ones already playing, without waiting for them.
    private func queue(_ samples: [Float], _ format: AVAudioFormat) throws {
        if !engine.isRunning {
            try engine.start()
            try player.playAudio()
        }
        player.scheduleBuffer(Self.buffer(samples, format))
    }

    private func speakWithPhoneVoice(_ sentences: [String]) {
        let utterance = AVSpeechUtterance(string: sentences.joined(separator: " "))
        utterance.voice = Self.bestVoice
        synthesizer.speak(utterance)
    }

    private static func buffer(_ samples: [Float], _ format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    /// The most natural phone voice installed for the phone's language: a Premium or Enhanced voice if the
    /// person downloaded one in Settings, otherwise the built-in one.
    private static var bestVoice: AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language && $0.voiceTraits.isDisjoint(with: [.isNoveltyVoice, .isPersonalVoice]) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if reading == nil, !self.synthesizer.isSpeaking { finished() } }
    }

    private func finished() {
        guard isSpeaking else { return }
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Kokoro-82M (Apache-2.0), an open voice model, converted to Core ML with 8-bit weights. It's bundled from
/// FieldCopilot/Kokoro, which `swift FieldCopilot/Scripts/fetch_voice.swift` fills, loaded on first use and
/// kept for the rest of the session.
actor NaturalVoice {
    static let shared = NaturalVoice()
    static let sampleRate = KokoroTTSModel.outputSampleRate
    /// A warm American English voice, Kokoro's best graded.
    static let voice = "af_heart"
    private static let folder = Bundle.main.url(forResource: "Kokoro", withExtension: nil)

    static var isBundled: Bool {
        folder.map { FileManager.default.fileExists(atPath: $0.appending(path: "kokoro_5s.mlmodelc").path) } ?? false
    }

    private var model: KokoroTTSModel?
    private var loading: Task<Void, Error>?

    /// One sentence as mono samples at `sampleRate`. Kokoro can't read digits: write numbers as words.
    func audio(for sentence: String) async throws -> [Float] {
        if model == nil {
            if loading == nil { loading = Task { try await load() } }
            try await loading!.value
        }
        return try model!.synthesize(text: sentence, voice: Self.voice)
    }

    private func load() async throws {
        // The Neural Engine, not the GPU: Core ML's GPU compiler rejects this model.
        model = try await KokoroTTSModel.fromPretrained(modelId: "aufklarer/Kokoro-82M-CoreML-INT8", cacheDir: Self.folder,
                                                        offlineMode: true, computeUnits: .cpuAndNeuralEngine)
    }
}

extension Scan {
    /// The results as a person would say them, one sentence each: brand and type, the model and serial
    /// character by character, when it was made, specs, ENERGY STAR, and a warning about a hard-to-read photo.
    var spokenSentences: [String] {
        guard let label else { return [title] }
        var sentences = [[label.brand.value, label.kind == .unknown ? nil : label.kind.displayName.lowercased()]
            .compactMap { $0 }.joined(separator: " ").nonEmpty ?? "Unknown equipment"]
        if let model = label.model.value { sentences.append("Model \(Spoken.characters(model))") }
        if let serial = label.serial.value { sentences.append("Serial \(Spoken.characters(serial))") }
        if let made, let madeDate {
            let month = madeDate.month.map { DateFormatter().monthSymbols[$0 - 1] + " " } ?? ""
            sentences.append("Made \(month)\(Spoken.year(madeDate.year)), \(made.age)")
        }
        if let size = label.size { sentences.append(Spoken.specs(size)) }
        if let listed = EquipmentDatabase.describe(label), let value = listed.field.value {
            let who = switch listed.title {
            case "ENERGY STAR": "ENERGY STAR"
            case "DOE": "the Department of Energy"
            default: "the California Energy Commission"
            }
            if label.listing == nil {
                sentences.append(listed.title == "DOE" ? "Not listed by the Department of Energy or ENERGY STAR" : "Not listed by \(who)")
            } else {
                sentences.append(listed.title == "ENERGY STAR" ? "ENERGY STAR certified, \(Spoken.specs(value))"
                                 : value == "Listed" ? "Listed by \(who)" : "Listed by \(who), \(Spoken.specs(value))")
            }
        }
        if let photoWarning { sentences.append(photoWarning) }
        return sentences.map { Spoken.numbers($0.hasSuffix(".") ? $0 : $0 + ".") }
    }
}

/// Text worded so any voice says it right, Kokoro included, which can't read digits: numbers as words,
/// model and serial numbers one character at a time, and specs the way a contractor says them.
nonisolated enum Spoken {
    /// A model or serial number one character at a time: "two, five, aitch, see, bee".
    static func characters(_ code: String) -> String {
        code.uppercased().compactMap { character in
            if let digit = character.wholeNumberValue { return digitNames[digit] }
            if let letter = letterNames[character] { return letter }
            return ["-": "dash", "/": "slash", ".": "dot"][character]
        }.joined(separator: ", ")
    }

    /// A year as people say it: "two thousand seven", "twenty thirteen", "nineteen ninety-eight".
    static func year(_ year: Int) -> String {
        let (century, rest) = (year / 100, year % 100)
        if (2000...2009).contains(year) { return spelled(year) }
        if rest == 0 { return "\(spelled(century)) hundred" }
        return "\(spelled(century)) \(rest < 10 ? "oh " : "")\(spelled(rest))"
    }

    /// Specs as they're said: "three tons, R four-ten ay", "ninety-five percent A F U E",
    /// "SEER two of fifteen point two to sixteen".
    static func specs(_ specs: String) -> String {
        var text = specs.replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: "–", with: " to ")
        text = text.replacing(#/\bR-(\d+)([A-Z]?)\b/#) { match in
            "R \(refrigerant(String(match.1)))\(match.2.isEmpty ? "" : " " + letterNames[Character(String(match.2))]!)"
        }
        text = text.replacing(#/\b(SEER2|EER2|HSPF2|UEF) (?=\d)/#) { "\($0.1) of " }
        text = text.replacing(#/ W\b/#, with: " watts").replacing(#/ gal\b/#, with: " gallons")
        for (written, said) in [("SEER2", "SEER two"), ("EER2", "E E R two"), ("HSPF2", "H S P F two"), ("AFUE", "A F U E"),
                                ("UEF", "U E F"), ("BTU/h", "B T U per hour"), ("%+", " percent or more"), ("%", " percent")] {
            text = text.replacingOccurrences(of: written, with: said)
        }
        return numbers(text)
    }

    /// Every number in the text as words: "15.2" is "fifteen point two", "80,000" is "eighty thousand".
    static func numbers(_ text: String) -> String {
        text.replacing(#/\d+(?:,\d{3})*(?:\.\d+)?/#) { match in
            Double(match.output.replacingOccurrences(of: ",", with: "")).map(spelled) ?? String(match.output)
        }
    }

    /// "R four-ten", "R four fifty-four", "R twenty-two": how refrigerant numbers are said.
    private static func refrigerant(_ digits: String) -> String {
        guard digits.count == 3, let first = digits.first?.wholeNumberValue, let rest = Int(digits.suffix(2)) else {
            return Int(digits).map(spelled) ?? digits
        }
        return "\(digitNames[first]) \(rest < 10 ? "oh " : "")\(spelled(rest))"
    }

    private static func spelled(_ number: some BinaryInteger) -> String { spelled(Double(number)) }

    private static func spelled(_ number: Double) -> String {
        speller.string(from: NSNumber(value: number)) ?? String(number)
    }

    private static let speller: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let digitNames = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    private static let letterNames: [Character: String] = [
        "A": "ay", "B": "bee", "C": "see", "D": "dee", "E": "ee", "F": "eff", "G": "gee", "H": "aitch", "I": "eye",
        "J": "jay", "K": "kay", "L": "el", "M": "em", "N": "en", "O": "oh", "P": "pee", "Q": "cue", "R": "ar",
        "S": "ess", "T": "tee", "U": "you", "V": "vee", "W": "double you", "X": "ex", "Y": "why", "Z": "zee",
    ]
}
