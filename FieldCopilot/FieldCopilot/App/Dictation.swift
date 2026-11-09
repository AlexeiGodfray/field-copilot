import AVFoundation
import Observation
import Speech

/// Listens to the microphone and turns speech into text as it's spoken, with Apple's on-device speech
/// recognizer. Nothing is recorded to a file, and no audio leaves the phone.
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        /// Getting the microphone and the speech model ready.
        case starting
        /// Downloading the speech model. Only the first time, and the phone keeps it for every app.
        case downloading
        case listening
        /// Settling the last words after the person stopped.
        case finishing
    }

    enum Problem: Equatable {
        case microphoneDenied
        case failed(String)
    }

    private(set) var state = State.idle
    /// Words the recognizer has settled on.
    private(set) var settled = ""
    /// The words being spoken now. They can still change.
    private(set) var tentative = ""
    /// The speech model download, while it's downloading.
    private(set) var download: Progress?
    var problem: Problem?

    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var capture: CaptureInputSequenceProvider?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var feeding: Task<Void, Never>?
    @ObservationIgnored private var results: Task<Void, Never>?
    /// Set when stop() is called while still getting ready.
    @ObservationIgnored private var stopRequested = false

    /// Everything heard so far.
    var text: String {
        [settled, tentative].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func start() async {
        guard state == .idle else { return }
        state = .starting
        stopRequested = false
        settled = ""
        tentative = ""
        problem = nil
        do {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: break
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .audio) else { return fail(.microphoneDenied) }
            default: return fail(.microphoneDenied)
            }
            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                return fail(.failed("This device has no microphone."))
            }
            guard let transcriber = await makeTranscriber() else {
                return fail(.failed("Voice notes aren't available in this phone's language."))
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                download = request.progress
                state = .downloading
                try await request.downloadAndInstall()
                download = nil
            }
            guard !stopRequested else { return stopNow() }

            let capture = try await CaptureInputSequenceProvider.providerWithSession(from: microphone, compatibleWith: [transcriber])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            // Our own input stream, so stopping can end it and the analyzer settles the last words.
            let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await analyzer.start(inputSequence: stream)
            let audio = capture.analyzerInputs
            feeding = Task.detached {
                do {
                    for try await buffer in audio { input.yield(buffer) }
                } catch {}
                input.finish()
            }
            self.capture = capture
            self.analyzer = analyzer
            self.input = input
            await Self.run(capture.captureSession)
            guard !stopRequested else { return stopNow() }
            state = .listening
        } catch {
            fail(.failed("Couldn't start listening. Try again."))
        }
    }

    /// Stops listening and returns everything that was said, once the last words are settled.
    func stop() async -> String {
        guard state == .listening else {
            // Still getting ready: start() gives up at its next step.
            stopRequested = true
            return ""
        }
        state = .finishing
        if let session = capture?.captureSession { await Self.halt(session) }
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        let said = text
        stopNow()
        return said
    }

    /// Stops without waiting for the last words.
    private func stopNow() {
        capture?.captureSession.stopRunning()
        input?.finish()
        feeding?.cancel()
        results?.cancel()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        capture = nil
        analyzer = nil
        input = nil
        feeding = nil
        results = nil
        download = nil
        state = .idle
    }

    private func fail(_ problem: Problem) {
        stopNow()
        self.problem = problem
    }

    /// The best transcriber this phone has, listening in the phone's language (or US English): the
    /// long-form speech model, or the dictation model on phones without it.
    private func makeTranscriber() async -> (any SpeechModule)? {
        if SpeechTranscriber.isAvailable, let locale = await Self.language(SpeechTranscriber.supportedLocale(equivalentTo:)) {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                                attributeOptions: [])
            results = Task {
                do {
                    for try await result in transcriber.results { heard(result.text, isFinal: result.isFinal) }
                } catch {}
            }
            return transcriber
        }
        if let locale = await Self.language(DictationTranscriber.supportedLocale(equivalentTo:)) {
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            results = Task {
                do {
                    for try await result in transcriber.results { heard(result.text, isFinal: result.isFinal) }
                } catch {}
            }
            return transcriber
        }
        return nil
    }

    /// The phone's language if the transcriber knows it, otherwise US English.
    private static func language(_ supported: (Locale) async -> Locale?) async -> Locale? {
        if let locale = await supported(.current) { return locale }
        return await supported(Locale(identifier: "en-US"))
    }

    private func heard(_ words: AttributedString, isFinal: Bool) {
        let words = String(words.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            settled = [settled, words].filter { !$0.isEmpty }.joined(separator: " ")
            tentative = ""
        } else {
            tentative = words
        }
    }

    // Starting and stopping a capture session blocks, so it's done off the main thread.

    private nonisolated static func run(_ session: AVCaptureSession) async {
        await Task.detached { if !session.isRunning { session.startRunning() } }.value
    }

    private nonisolated static func halt(_ session: AVCaptureSession) async {
        await Task.detached { session.stopRunning() }.value
    }
}
