//
//  ContentView.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import UniformTypeIdentifiers
import AVFoundation
import Combine
import Network
#if canImport(HealthKit)
import HealthKit
#endif

private extension Color {
    // Sprint E #6: fonte da cor agora vive em Assets.xcassets/BrandYellow.colorset
    // com variantes light + dark (light: 1.0/0.82/0.02; dark: 0.95/0.78/0.10 —
    // menos saturado pra evitar "bolha amarela" em fundo escuro). O nome do
    // asset é "BrandYellow" pra não colidir com o símbolo autogerado pela
    // Color Asset Symbols do iOS 17+ que vira `Color.neuroYellow`.
    static let neuroYellow = Color("BrandYellow")
    static let neuroGold = Color(red: 1.0, green: 0.66, blue: 0.0)
    static let neuroOrange = Color(red: 1.0, green: 0.48, blue: 0.0)
}

private extension UIColor {
    static let neuroGold = UIColor(red: 1.0, green: 0.66, blue: 0.0, alpha: 1)
}

private final class PPGCameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isMeasuring = false
    @Published var status = "Pronto para medir com câmera."
    @Published var heartRate = 0.0
    @Published var hrv = 0.0
    @Published var respiration = 0.0
    @Published var perfusion = 0.0
    @Published var stress = 0.0
    @Published var signalQuality = 0.0

    private let session = AVCaptureSession()
    /// Capture pipeline lives on this serial queue: input frames write to
    /// `samples` here. Keep work on this queue short so we don't back-pressure
    /// the AV pipeline and drop frames.
    private let queue = DispatchQueue(label: "neuroflow.ppg.camera")
    /// Analysis runs on its own queue with a snapshot of the samples taken on
    /// the capture queue. Peak picking + RMSSD used to run on `queue` itself,
    /// blocking subsequent frames.
    private let analysisQueue = DispatchQueue(label: "neuroflow.ppg.analysis", qos: .userInitiated)
    private var samples: [(time: TimeInterval, value: Double)] = []
    private var device: AVCaptureDevice?

    func start() {
        guard !isMeasuring else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            if granted {
                self.queue.async { self.startSession() }
            } else {
                DispatchQueue.main.async { self.status = "Permissão da câmera negada." }
            }
        }
    }

    func stop() {
        queue.async {
            self.session.stopRunning()
            self.setTorch(active: false)
            DispatchQueue.main.async {
                self.isMeasuring = false
                self.status = self.heartRate > 0 ? "Leitura finalizada." : "Medição interrompida."
            }
        }
    }

    private func startSession() {
        samples.removeAll()
        session.beginConfiguration()
        session.sessionPreset = .low
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.status = "Câmera traseira indisponível." }
            session.commitConfiguration()
            return
        }

        device = camera
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        setTorch(active: true)
        session.startRunning()

        DispatchQueue.main.async {
            self.isMeasuring = true
            self.status = "Cubra câmera e flash com o dedo. Fique parado por 30 segundos."
        }
    }

    private func setTorch(active: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if active {
                try device.setTorchModeOn(level: 0.75)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { self.status = "Não foi possível controlar o flash." }
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let startX = width / 3
        let endX = width * 2 / 3
        let startY = height / 3
        let endY = height * 2 / 3
        var redTotal = 0.0
        var brightnessTotal = 0.0
        var count = 0.0

        for y in stride(from: startY, to: endY, by: 12) {
            for x in stride(from: startX, to: endX, by: 12) {
                let offset = y * bytesPerRow + x * 4
                let blue = Double(buffer[offset])
                let green = Double(buffer[offset + 1])
                let red = Double(buffer[offset + 2])
                redTotal += red
                brightnessTotal += (red + green + blue) / 3
                count += 1
            }
        }

        guard count > 0 else { return }
        let redMean = redTotal / count
        let brightness = brightnessTotal / count
        let time = Date().timeIntervalSince1970

        queue.async {
            self.samples.append((time: time, value: redMean))
            self.samples = self.samples.filter { time - $0.time <= 35 }
            if self.samples.count % 12 == 0 {
                let snapshot = self.samples
                self.analysisQueue.async {
                    self.analyzeSamples(snapshot: snapshot, brightness: brightness)
                }
            }
        }
    }

    private func analyzeSamples(snapshot samples: [(time: TimeInterval, value: Double)], brightness: Double) {
        guard samples.count > 60 else {
            DispatchQueue.main.async { self.signalQuality = min(max(brightness / 180, 0), 1) }
            return
        }

        let values = samples.map(\.value)
        let mean = values.reduce(0, +) / Double(values.count)
        let centered = values.map { $0 - mean }
        let fast = movingAverage(centered, window: 5)
        let slow = movingAverage(centered, window: 25)
        let smoothed = zip(fast, slow).map { $0 - $1 }
        let amplitude = percentile(smoothed, 0.95) - percentile(smoothed, 0.05)
        let derivative = zip(smoothed.dropFirst(), smoothed).map { abs($0 - $1) }
        let motionPenalty = min((standardDeviation(derivative) / max(amplitude, 1)) * 2.8, 1)
        let pressureQuality = min(max((brightness - 70) / 95, 0), 1)
        let amplitudeQuality = min(max(amplitude / 18, 0), 1)
        let saturationPenalty = brightness > 245 || brightness < 55 ? 0.35 : 0
        let quality = min(max(pressureQuality * amplitudeQuality * (1 - motionPenalty) - saturationPenalty, 0), 1)
        let threshold = max(amplitude * 0.22, standardDeviation(smoothed) * 0.72)
        var peaks: [TimeInterval] = []

        for index in 2..<(smoothed.count - 2) {
            let localProminence = smoothed[index] - max(smoothed[index - 2], smoothed[index + 2])
            if smoothed[index] > smoothed[index - 1],
               smoothed[index] > smoothed[index + 1],
               smoothed[index] >= smoothed[index - 2],
               smoothed[index] >= smoothed[index + 2],
               smoothed[index] > threshold,
               localProminence > standardDeviation(smoothed) * 0.18,
               peaks.last.map({ samples[index].time - $0 > 0.38 }) ?? true {
                peaks.append(samples[index].time)
            }
        }

        let recentPeaks = peaks.filter { (samples.last?.time ?? 0) - $0 <= 30 }
        let intervals = zip(recentPeaks.dropFirst(), recentPeaks)
            .map { $0 - $1 }
            .filter { (0.42...1.5).contains($0) }
        guard intervals.count >= 3 else {
            DispatchQueue.main.async {
                self.signalQuality = quality
                if brightness < 70 {
                    self.status = "Pouca pressão/luz. Cubra câmera e flash com o dedo."
                } else if saturationPenalty > 0 {
                    self.status = "Pressão ou luz excessiva. Ajuste o dedo sobre a câmera."
                } else if motionPenalty > 0.55 {
                    self.status = "Movimento detectado. Mantenha o dedo parado."
                } else {
                    self.status = quality < 0.35 ? "Sinal fraco. Ajuste dedo, luz e movimento." : "Coletando batimentos..."
                }
            }
            return
        }

        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        let intervalDeviation = standardDeviation(intervals)
        let cleanIntervals = intervals.filter { abs($0 - averageInterval) <= max(intervalDeviation * 2.2, 0.08) }
        guard cleanIntervals.count >= 4 else {
            DispatchQueue.main.async {
                self.signalQuality = max(quality - 0.18, 0)
                self.status = "Picos inconsistentes. Mantenha dedo parado por mais tempo."
            }
            return
        }
        let cleanAverageInterval = cleanIntervals.reduce(0, +) / Double(cleanIntervals.count)
        // N-I3: store the raw physiological value — do NOT clamp to 40-160.
        // Clamping would mask bradycardia (<40 BPM, e.g. lithium side-effect)
        // and tachycardia (>160 BPM, e.g. manic episode) from the clinician.
        // Signal quality is halved when the value is outside the plausible
        // resting range so the UI can display a low-confidence indicator.
        let bpm = 60 / cleanAverageInterval
        let bpmIsPlausible = bpm >= 40 && bpm <= 200
        let adjustedQuality = bpmIsPlausible ? quality : quality * 0.5
        let hrvMs = cleanIntervals.count >= 20 && quality >= 0.65
            ? min(max(rmssd(cleanIntervals) * 1000, 5), 180)
            : 0
        let perfusionIndex = min(max(amplitude / max(mean, 1) * 100, 0), 20)
        let snapshotDuration = (samples.last?.time ?? 0) - (samples.first?.time ?? 0)
        let respirationEstimate = quality >= 0.55
            ? respirationFromSlowWave(values: centered, duration: snapshotDuration)
            : 0
        let hrvForStress = hrvMs > 0 ? hrvMs : 45
        let stressIndex = min(max((bpm - 55) * 0.8 + (70 - hrvForStress) * 0.7 + (1 - quality) * 25, 0), 100)

        DispatchQueue.main.async {
            self.signalQuality = adjustedQuality
            self.heartRate = bpm
            self.hrv = hrvMs
            self.perfusion = perfusionIndex
            self.respiration = respirationEstimate
            self.stress = stressIndex
            if quality < 0.45 {
                self.status = "Sinal instável. Reposicione o dedo."
            } else if hrvMs == 0 {
                self.status = "Batimentos detectados. HRV exige sinal limpo e janela maior."
            } else {
                self.status = "Leitura PPG real atualizada com picos consistentes."
            }
        }
    }

    private func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard values.count >= window else { return values }
        return values.indices.map { index in
            let start = max(0, index - window / 2)
            let end = min(values.count - 1, index + window / 2)
            let slice = values[start...end]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }

    private func rmssd(_ intervals: [Double]) -> Double {
        guard intervals.count > 2 else { return 0 }
        let differences = zip(intervals.dropFirst(), intervals).map { $0 - $1 }
        let squaredMean = differences.map { $0 * $0 }.reduce(0, +) / Double(differences.count)
        return sqrt(squaredMean)
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(max(Int(Double(sorted.count - 1) * percentile), 0), sorted.count - 1)
        return sorted[index]
    }

    private func respirationFromSlowWave(values: [Double], duration: TimeInterval) -> Double {
        guard values.count > 180 else { return 0 }
        let slow = movingAverage(values, window: 75)
        let mean = slow.reduce(0, +) / Double(slow.count)
        let centered = slow.map { $0 - mean }
        guard standardDeviation(centered) > 0.4 else { return 0 }
        var crossings = 0
        for index in 1..<centered.count where centered[index - 1] < 0 && centered[index] >= 0 {
            crossings += 1
        }
        let safeDuration = max(duration, 1)
        let breathsPerMinute = Double(crossings) / safeDuration * 60
        guard (6...28).contains(breathsPerMinute) else { return 0 }
        return breathsPerMinute
    }
}

private final class VoiceSignalManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var status = "Nenhuma amostra de voz."
    @Published var averagePower = 0.0
    @Published var pauseRatio = 0.0
    @Published var variability = 0.0
    @Published var fundamentalFrequency = 0.0
    @Published var pitchVariability = 0.0
    @Published var syllableEnergy = 0.0
    @Published var rhythm = 0.0

    private let engine = AVAudioEngine()
    /// Serial queue that drives pitch estimation and RMS accumulation. The tap
    /// callback used to do all this work on AVAudioEngine's internal thread
    /// AND hop to main to publish each frame, causing UI thrashing under load.
    /// Heavy work stays here; published properties flush in `analyze()` only.
    private let processingQueue = DispatchQueue(label: "neuroflow.voice.processing", qos: .userInitiated)
    private var timer: Timer?
    private var powers: [Double] = []
    private var pitches: [Double] = []
    private var speechEnergies: [Double] = []
    private var speechBursts = 0
    private var wasSpeaking = false
    private var recordingStartedAt = Date()

    func start() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    granted ? self.startRecording() : (self.status = "Permissão do microfone negada.")
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    granted ? self.startRecording() : (self.status = "Permissão do microfone negada.")
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        // Drain the processing queue (any in-flight buffers finish) then
        // compute aggregates from a snapshot and publish on the main actor.
        processingQueue.async { [weak self] in
            self?.analyzeSnapshot()
        }
    }

    private func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)

            // Reset the accumulator arrays ON the processing queue so any
            // in-flight tap callbacks queued before this call finish first,
            // avoiding a race where the reset wipes data the next buffer is
            // about to append (B23).
            processingQueue.sync {
                powers.removeAll()
                pitches.removeAll()
                speechEnergies.removeAll()
                speechBursts = 0
                wasSpeaking = false
            }
            recordingStartedAt = Date()
            isRecording = true
            status = "Lendo intensidade, pausas e frequência vocal sem salvar áudio."

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                // Hop off the AVAudioEngine internal thread so pitch
                // estimation never blocks the audio rendering pipeline.
                self?.processingQueue.async {
                    self?.processAudioBuffer(buffer, sampleRate: format.sampleRate)
                }
            }
            try engine.start()

            timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                self?.stop()
            }
        } catch {
            status = "Falha ao iniciar voz: \(error.localizedDescription)"
        }
    }

    /// Runs entirely on `processingQueue`. Mutates accumulator arrays without
    /// touching `@Published` properties — those are flushed in `analyze()` to
    /// avoid one main-thread hop per audio buffer.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sumSquares = 0.0

        for index in 0..<frameCount {
            let sample = Double(channel[index])
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Double(frameCount))
        let normalizedPower = min(max(rms * 12, 0), 1)
        let pitchEstimate = estimatePitch(channel: channel, frameCount: frameCount, sampleRate: sampleRate)
        let isVoiceLike = normalizedPower > 0.08 && (70...350).contains(pitchEstimate)

        powers.append(normalizedPower)
        if isVoiceLike {
            pitches.append(pitchEstimate)
            speechEnergies.append(normalizedPower)
        }
        if isVoiceLike && !wasSpeaking {
            speechBursts += 1
        }
        wasSpeaking = isVoiceLike
    }

    /// Executes on `processingQueue`. Computes aggregates from local snapshots
    /// and publishes them once on the main actor, instead of touching the
    /// `@Published` properties from inside the audio callback.
    private func analyzeSnapshot() {
        guard !powers.isEmpty else { return }

        let powersSnapshot = powers
        let pitchesSnapshot = pitches
        let energiesSnapshot = speechEnergies
        let burstsSnapshot = speechBursts
        let recordingStart = recordingStartedAt

        let avgPower = powersSnapshot.reduce(0, +) / Double(powersSnapshot.count)
        let pause = Double(powersSnapshot.filter { $0 < 0.08 }.count) / Double(powersSnapshot.count)
        let variation = sqrt(powersSnapshot.map { pow($0 - avgPower, 2) }.reduce(0, +) / Double(powersSnapshot.count))
        let pitchMean = pitchesSnapshot.isEmpty ? 0 : pitchesSnapshot.reduce(0, +) / Double(pitchesSnapshot.count)
        let pitchVar = pitchesSnapshot.isEmpty ? 0 : standardDeviation(pitchesSnapshot)
        let syllable = energiesSnapshot.isEmpty ? 0 : energiesSnapshot.reduce(0, +) / Double(energiesSnapshot.count)
        let minutes = max(Date().timeIntervalSince(recordingStart) / 60, 0.01)
        let rhythmValue = Double(burstsSnapshot) / minutes

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.averagePower = avgPower
            self.pauseRatio = pause
            self.variability = variation
            self.fundamentalFrequency = pitchMean
            self.pitchVariability = pitchVar
            self.syllableEnergy = syllable
            self.rhythm = rhythmValue
            self.status = "Voz analisada sem salvar conteúdo: pitch, pausas, ritmo e energia por fala."
        }
    }

    private func estimatePitch(channel: UnsafePointer<Float>, frameCount: Int, sampleRate: Double) -> Double {
        let minLag = max(Int(sampleRate / 350), 1)
        let maxLag = min(Int(sampleRate / 70), frameCount / 2)
        guard maxLag > minLag else { return 0 }

        var bestLag = 0
        var bestCorrelation = 0.0
        for lag in minLag...maxLag {
            var correlation = 0.0
            var energy = 0.0
            for index in 0..<(frameCount - lag) {
                let current = Double(channel[index])
                let delayed = Double(channel[index + lag])
                correlation += current * delayed
                energy += current * current + delayed * delayed
            }
            let normalized = energy > 0 ? (2 * correlation / energy) : 0
            if normalized > bestCorrelation {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        guard bestCorrelation > 0.32, bestLag > 0 else { return 0 }
        return sampleRate / Double(bestLag)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

struct MedicationPlanEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var dose: String
    var schedule: String
    var prescription: String
    var changeNote: String
    var createdAt = Date()

    var summary: String {
        [name, dose, schedule]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

struct CustomSymptomEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var value: Double
    var createdAt = Date()
}

private extension Array where Element == BackendUser {
    var sortedByRisk: [BackendUser] {
        sorted { first, second in
            (first.riskScore ?? -1) > (second.riskScore ?? -1)
        }
    }
}

enum OfflineSyncKind: String, Codable {
    case checkIn
    case assessment
    case report
}

struct OfflineSyncItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: OfflineSyncKind
    var payloadJSON: String
    var summary: String
    var createdAt = Date()
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var patients: [PatientProfile]
    @Query private var checkIns: [DailyCheckIn]
    @Query private var assessments: [ScaleAssessment]
    @Query private var alerts: [ClinicalAlert]
    @Query private var reports: [ClinicalReport]
    @StateObject private var ppgManager = PPGCameraManager()
    @StateObject private var voiceManager = VoiceSignalManager()
    // Sprint E #4: cache central para evitar re-sort + re-summary em cada body.
    // sortedCheckIns/sortedAssessments/summary leem do store quando isReady;
    // o `.task(id:)` no body raiz dispara recompute quando contagens mudam.
    @State private var patientStore = PatientStore()

    // Drafts now go through DraftStore: AES-GCM ciphertext in UserDefaults,
    // with the symmetric key kept in the Keychain. Sprint 12 had them in
    // plaintext @AppStorage, which leaked PHI through iCloud Backup of the
    // standard plist (Sprint 16 / F13' / S15).
    @EncryptedDraft("neuroflowDraftMood", defaultValue: 3.0) private var mood
    @EncryptedDraft("neuroflowDraftAnxiety", defaultValue: 2.0) private var anxiety
    @EncryptedDraft("neuroflowDraftEnergy", defaultValue: 3.0) private var energy
    @EncryptedDraft("neuroflowDraftIrritability", defaultValue: 1.0) private var irritability
    @EncryptedDraft("neuroflowDraftSleepHours", defaultValue: 7.0) private var sleepHours
    @EncryptedDraft("neuroflowDraftAppetite", defaultValue: 3.0) private var appetite
    // P2-7: default 0.0 = "Não se aplica" para evitar ruído com valor médio.
    @EncryptedDraft("neuroflowDraftLibido", defaultValue: 0.0) private var libido
    @State private var medicationStatus = MedicationStatus.taken
    @State private var safetyStatus = SafetyStatus.safe
    // Same DraftStore encryption applies to the free-text fields, which are
    // the most sensitive of the bunch (Sprint 16 / F13' / S15).
    @EncryptedDraft("neuroflowDraftSideEffects", defaultValue: "") private var sideEffects
    @EncryptedDraft("neuroflowDraftAutomaticThoughts", defaultValue: "") private var automaticThoughts
    @EncryptedDraft("neuroflowDraftJournalEntry", defaultValue: "") private var journalEntry
    @State private var selectedCareFocus = CareFocus.bipolar
    @State private var alcoholTrigger = false
    @State private var poorSleepTrigger = false
    @State private var stressTrigger = false
    @State private var conflictTrigger = false
    @State private var routineChangeTrigger = false
    @State private var menstrualTrigger = false
    @State private var customTriggerText = ""
    @State private var customTriggers: [String] = []
    @State private var selectedScale = ScaleKind.phq9
    @State private var scaleAnswers: [ScaleKind: [Int]] = [:]
    @State private var reportPreview = ""
    @State private var reportPDFURL: URL?
    @State private var reportCSVURL: URL?
    @State private var backupURL: URL?
    @State private var saveStatusMessage = ""
    @State private var scaleStatusMessage = ""
    @State private var reportStatusMessage = ""
    // P1-2 (UX): sistema central de toasts — substitui as 9 variáveis de
    // status espalhadas. Nível: .error (vermelho, persistente até dismiss),
    // .warning (laranja, 4 s), .success (verde, 2 s).
    @State private var toastMessage: String = ""
    @State private var toastLevel: ToastLevel = .success
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var selectedPatientPage = PatientPage.diary
    // M2 (UX-P0): seções recolhíveis do diário — reduz carga cognitiva
    // para pacientes com pouca energia. Todas abertas por padrão.
    @State private var diarySection1Expanded = true  // "Como você está?"
    @State private var diarySection2Expanded = true  // "Segurança e medicação"
    @State private var diarySection3Expanded = true  // "Texto livre e gatilhos"
    // M5 (UX-P0): aba ativa no TabView do clínico
    @State private var clinicianTab: ClinicianTab = .patients
    // Sprint A: confirmação antes de aplicar troca de perfil de acesso.
    // Toque acidental no Picker antes mudava a TabView raiz sem aviso.
    @State private var roleChangePending: AccessRole?
    // Sprint A: debounce do botão Save. O dayKey @Attribute(.unique) do
    // commit M5 não tolera duas execuções concorrentes do mesmo dia.
    @State private var isSavingCheckIn = false
    @State private var loginEmail = ""
    @State private var loginPassword = ""
    @State private var fullName = ""
    @State private var isCreatingAccount = false
    @State private var isRequestingPasswordReset = false
    @State private var patientLinkEmail = ""
    @State private var clinicianPatients: [BackendUser] = []
    @State private var selectedRemotePatient: BackendUser?
    @State private var clinicianPatientFilter: ClinicianPatientFilter = .all
    @State private var sentInvitesFilter: SentInviteStatusFilter = .all
    @State private var remotePatientSubTab: RemotePatientSubTab = .overview
    @State private var isLoadingRemotePatientData = false
    @State private var evolutionSearchQuery = ""
    @State private var evolutionFilter: EvolutionFilter = .all
    @State private var isShowingBodySignalsTechnicalDetails = false
    @State private var remoteCheckIns: [BackendDailyCheckIn] = []
    @State private var remoteAssessments: [BackendScaleAssessment] = []
    @State private var remoteAlerts: [BackendClinicalAlert] = []
    @State private var remoteReports: [BackendClinicalReport] = []
    @State private var caregiverName = ""
    @State private var caregiverRelationship = ""
    @State private var remoteCaregivers: [BackendCaregiverContact] = []
    @State private var clinicianPatientStatusMessage = ""
    @State private var remotePatientStatusMessage = ""
    @State private var isAuthenticating = false
    @State private var loginStatusMessage = ""
    @State private var isShowingSettings = false
    @State private var isShowingScales = false
    @State private var isImportingBackup = false
    @State private var medicationPlans: [MedicationPlanEntry] = []
    @State private var customSymptoms: [CustomSymptomEntry] = []
    @State private var offlineSyncQueue: [OfflineSyncItem] = []
    // N-I2: watch network path changes and automatically flush the offline
    // queue when connectivity is restored without requiring user interaction.
    @State private var networkMonitor = NWPathMonitor()
    @State private var networkMonitorQueue = DispatchQueue(label: "io.neuroflow.networkMonitor", qos: .background)
    @State private var typingStartedAt: Date?
    @State private var bodySignalTypingLatency = 0.0
    @State private var bodySignalTypingSpeed = 0.0
    @State private var bodySignalInteractionCount = 0
    @State private var appSessionStartedAt = Date()
    @KeychainStored(.authToken) private var authToken
    @KeychainStored(.refreshToken) private var refreshToken
    // N-I4: email and name are PII — Keychain instead of UserDefaults plaintext.
    // Legacy @AppStorage values are auto-migrated on first launch by
    // KeychainStore.migrateLegacyTokenIfNeeded() (called in AppDelegate).
    @KeychainStored(.userEmail) private var authenticatedEmail
    @KeychainStored(.userName) private var authenticatedName
    @KeychainStored(.userRole) private var authenticatedRole
    @AppStorage("neuroflowUserId") private var authenticatedUserId = 0
    @AppStorage("neuroflowMedicationReminderEnabled") private var medicationReminderEnabled = false
    @AppStorage("neuroflowCheckInReminderEnabled") private var checkInReminderEnabled = false
    @AppStorage("neuroflowMedicationReminderHour") private var medicationReminderHour = 9
    @AppStorage("neuroflowCheckInReminderHour") private var checkInReminderHour = 20
    // PHI: medication fields are encrypted at rest via AES-GCM (DraftStore).
    // Legacy @AppStorage values are auto-migrated on first read.
    @EncryptedDraft("neuroflowMedicationName", defaultValue: "") private var medicationName
    @EncryptedDraft("neuroflowMedicationDose", defaultValue: "") private var medicationDose
    @EncryptedDraft("neuroflowMedicationSchedule", defaultValue: "") private var medicationSchedule
    @EncryptedDraft("neuroflowMedicationChangeNote", defaultValue: "") private var medicationChangeNote
    @EncryptedDraft("neuroflowMedicationPrescription", defaultValue: "") private var medicationPrescription
    @EncryptedDraft("neuroflowMedicationPlansData", defaultValue: "") private var medicationPlansData
    @AppStorage("neuroflowCustomSymptomName") private var customSymptomName = ""
    @AppStorage("neuroflowCustomSymptomValue") private var customSymptomValue = 3.0
    @AppStorage("neuroflowCustomSymptomsData") private var customSymptomsData = ""
    @EncryptedDraft("neuroflowSafetyContact", defaultValue: "") private var safetyContact
    @EncryptedDraft("neuroflowSafetyWarningSigns", defaultValue: "") private var safetyWarningSigns
    @EncryptedDraft("neuroflowSafetyStrategies", defaultValue: "") private var safetyStrategies
    @AppStorage("neuroflowNextAppointmentAt") private var nextAppointmentAt = Date().addingTimeInterval(60 * 60 * 24 * 30).timeIntervalSince1970
    @AppStorage("neuroflowNextAppointmentNote") private var nextAppointmentNote = ""
    @AppStorage("neuroflowAutoMonthlyReportEnabled") private var autoMonthlyReportEnabled = false
    @AppStorage("neuroflowAutoBackupEnabled") private var autoBackupEnabled = true
    @AppStorage("neuroflowBackupIntervalDays") private var backupIntervalDays = 7
    @AppStorage("neuroflowLastAutomaticBackupAt") private var lastAutomaticBackupAt = 0.0
    @AppStorage("neuroflowAutoCareTeamSendEnabled") private var autoCareTeamSendEnabled = false
    @AppStorage("neuroflowCareTeamContact") private var careTeamContact = ""
    @AppStorage("neuroflowCareTeamSendStatus") private var careTeamSendStatus = "Envio automático inativo"
    @AppStorage("neuroflowShareWithCaregiver") private var shareWithCaregiver = false
    @AppStorage("neuroflowHealthKitEnabled") private var healthKitEnabled = false
    @AppStorage("neuroflowHealthKitStatus") private var healthKitStatus = "Apple Health não conectado"
    @AppStorage("neuroflowHealthSteps") private var healthSteps = 0
    @AppStorage("neuroflowHealthSleepHours") private var healthSleepHours = 0.0
    @AppStorage("neuroflowHealthHeartRate") private var healthHeartRate = 0.0
    @AppStorage("neuroflowHealthActiveEnergy") private var healthActiveEnergy = 0.0
    @AppStorage("neuroflowRemotePushEnabled") private var remotePushEnabled = false
    @AppStorage("neuroflowRemotePushStatus") private var remotePushStatus = "Push remoto não configurado"
    @KeychainStored(.apnsDeviceToken) private var apnsDeviceToken
    @AppStorage("neuroflowBackgroundBackupStatus") private var backgroundBackupStatus = "Backup em segundo plano não agendado"
    // lastBackupJSON was removed (S15/C1): PHI must not live in UserDefaults.
    // The backup file is written directly to BackupStore.protectedFileURL.
    @AppStorage("neuroflowOfflineSyncQueueData") private var offlineSyncQueueData = ""
    @AppStorage("neuroflowLastSyncStatus") private var lastSyncStatus = "Salvo no aparelho"
    @AppStorage("neuroflowBiometricConsentAccepted") private var biometricConsentAccepted = false
    @AppStorage("neuroflowPrivacyRetentionDays") private var privacyRetentionDays = 365
    @State private var privacyStatusMessage = ""
    @State private var privacyExportURL: URL?
    @State private var isConfirmingClinicalWipe = false
    @State private var isConfirmingAccountDelete = false
    @State private var isShowingAuditLogs = false
    @State private var remoteAuditLogs: [BackendAuditLog] = []
    @State private var caregiverEditTarget: BackendCaregiverContact?
    @State private var caregiverStatusMessage = ""
    @State private var caregiverEditName = ""
    @State private var caregiverEditContact = ""
    @State private var caregiverEditRelationship = ""
    @State private var caregiverEditShareEnabled = true
    @State private var isSavingCaregiverEdit = false
    @State private var pendingClinicianInvites: [BackendClinicianInvite] = []
    @State private var inviteStatusMessage = ""
    @State private var clinicianSentInvites: [BackendSentInvite] = []
    @State private var isLoadingClinicianSentInvites = false
    @State private var clinicianSentInvitesFlash = ""
    @State private var isShowingSessionExpiredAlert = false
    @State private var isShowingPasswordResetConfirm = false
    @State private var isShowingCrisisSheet = false
    @State private var isShowingLoginSheet = false
    @State private var isShowingPostSavePrompt = false
    @State private var postSaveThought = ""
    @AppStorage("neuroflowOnboardingComplete") private var hasCompletedOnboarding = false
    @AppStorage("neuroflowMoodCoachmarkSeen") private var hasSeenMoodCoachmark = false
    @State private var onboardingStep = 0
    /// Timestamp (timeIntervalSince1970) até quando o banner de convite fica
    /// escondido. Zero quando nunca foi adiado.
    @AppStorage("neuroflowInviteSnoozedUntil") private var inviteSnoozedUntil = 0.0
    @State private var passwordResetCode = ""
    @State private var passwordResetNewPassword = ""
    @State private var passwordResetStatusMessage = ""
    @State private var isConfirmingPasswordReset = false
    @State private var linkedClinicians: [BackendLinkedClinician] = []
    @State private var linkedCliniciansStatusMessage = ""
    @State private var clinicianToRevoke: BackendLinkedClinician?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPrivacyShielded = false

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    // Sprint E #4: leitura cache-first. Fallback (recomputa) só roda no primeiro
    // frame antes do `.task(id:)` no body popular o store. Resto é O(1).
    private var sortedCheckIns: [DailyCheckIn] {
        patientStore.isReady ? patientStore.sortedCheckIns : checkIns.sorted { $0.date > $1.date }
    }

    private var sortedAssessments: [ScaleAssessment] {
        patientStore.isReady ? patientStore.sortedAssessments : assessments.sorted { $0.date > $1.date }
    }

    private var activeAlerts: [ClinicalAlert] { patientStore.activeAlerts }
    private var latestReports: [ClinicalReport] { patientStore.latestReports }

    // Sprint 25: query normalizada para casamento "contém" insensível a caixa.
    private var evolutionQueryNormalized: String {
        evolutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func evolutionMatches(_ haystacks: [String]) -> Bool {
        let query = evolutionQueryNormalized
        guard !query.isEmpty else { return true }
        return haystacks.contains { $0.localizedLowercase.contains(query) }
    }

    private var filteredCheckIns: [DailyCheckIn] {
        sortedCheckIns.filter { checkIn in
            evolutionMatches([
                checkIn.journalEntry,
                checkIn.automaticThoughts,
                checkIn.sideEffects,
            ])
        }
    }

    private var filteredAssessments: [ScaleAssessment] {
        sortedAssessments.filter { assessment in
            evolutionMatches([assessment.scaleName, assessment.interpretation])
        }
    }

    private var filteredActiveAlerts: [ClinicalAlert] {
        activeAlerts.filter { alert in
            evolutionMatches([alert.title, alert.message])
        }
    }

    // Sprint E #4: lê do cache quando isReady. Cai no recompute só no primeiro
    // frame, antes do `.task(id:)` no body rodar `patientStore.recompute`.
    private var summary: LongitudinalSummary {
        if let cached = patientStore.summary { return cached }
        return ClinicalAnalysis.summary(checkIns: sortedCheckIns, assessments: sortedAssessments)
    }

    /// Lightweight fingerprint for the fields that drive LongitudinalSummary.
    /// Changes to mood, anxiety, sleep, medication adherence, or any scale
    /// score invalidate the PatientStore cache and trigger a recompute.
    /// Free-text fields (journal, side-effects) are excluded because they
    /// don't affect the computed summary and omitting them keeps this cheap.
    // Sprint A (REG-3): cheap key — apenas contagens dos 4 arrays. O fingerprint
    // pesado (que itera mood/anxiety/sleep/...) só roda dentro de
    // `recomputeStoreFingerprintIfNeeded()` quando count muda. Antes do fix,
    // o `.task(id: storeFingerprint)` chamava o getter em cada body re-eval,
    // disparando um loop O(n) sobre todos os check-ins por render.
    private var storeFingerprintCheap: String {
        // N-C3: include the number of acknowledged alerts so that ack-ing an
        // alert fires .task(id:) and patientStore.recompute() removes it from
        // activeAlerts. Without this, acknowledged alerts stay visible until
        // another count-changing event happens.
        let ackedCount = alerts.filter(\.acknowledged).count
        return "\(checkIns.count)-\(assessments.count)-\(alerts.count)-\(ackedCount)-\(reports.count)"
    }

    private func computeFullStoreFingerprint() -> String {
        // Sub-expressões nomeadas: a versão original (commit 413f734) juntava
        // tudo em uma única expressão e o type-checker do Swift estourava o
        // limite ("unable to type-check in reasonable time").
        let checkInSignal = checkIns.reduce(into: 0) { acc, c in
            let mood = Int(c.mood * 10)
            let anxiety = Int(c.anxiety * 10)
            let sleep = Int(c.sleepHours * 10)
            let med: Int = c.medicationTaken ? 1 : 0
            let suicidal: Int = c.suicidalIdeation ? 100 : 0
            acc += mood + anxiety + sleep + med + suicidal
        }
        let assessmentSignal = assessments.reduce(0) { $0 + $1.score }
        let alertSignal = alerts.reduce(into: 0) { acc, a in
            acc += a.acknowledged ? 1 : 0
        }
        let reportSignal = reports.count
        return "\(checkIns.count)-\(assessments.count)-\(checkInSignal)-\(assessmentSignal)-\(alerts.count)-\(alertSignal)-\(reportSignal)"
    }

    private var selectedScaleAnswers: [Int] {
        scaleAnswers[selectedScale] ?? Array(repeating: 0, count: selectedScale.questions.count)
    }

    private var selectedScaleScore: Int {
        ClinicalAnalysis.score(for: selectedScale, answers: selectedScaleAnswers)
    }

    private var selectedScaleInterpretation: String {
        ClinicalAnalysis.interpretation(for: selectedScale, score: selectedScaleScore)
    }

    private var automaticCheckupResults: [AutomaticScaleResult] {
        ScaleKind.allCases.map { scale in
            let answers = automaticAnswers(for: scale)
            let score = ClinicalAnalysis.score(for: scale, answers: answers)
            return AutomaticScaleResult(
                scale: scale,
                answers: answers,
                score: score,
                interpretation: ClinicalAnalysis.interpretation(for: scale, score: score)
            )
        }
    }

    private var neuroFlowRiskSignature: NeuroFlowRiskSignature {
        NeuroFlowRiskSignature.calculate(
            summary: summary,
            checkIns: sortedCheckIns,
            scaleResults: automaticCheckupResults,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggerLabels,
            textAssessment: currentTextAssessment,
            ppgStress: ppgManager.stress,
            ppgQuality: ppgManager.signalQuality,
            voicePauseRatio: voiceManager.pauseRatio,
            typingSpeed: bodySignalTypingSpeed,
            careFocus: selectedCareFocus
        )
    }

    private var nextAppointmentDateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: nextAppointmentAt) },
            set: { nextAppointmentAt = $0.timeIntervalSince1970 }
        )
    }

    private var currentTextAssessment: TextRiskAssessment {
        safetyStatus == .urgent
            ? TextRiskAssessment(level: .high, detectedTerms: ["triagem positiva"], explanation: "A triagem estruturada marcou ideação suicida.")
            : ClinicalAnalysis.textAssessment(for: "\(journalEntry) \(automaticThoughts)")
    }

    private var activeRole: AccessRole {
        AccessRole(rawValue: patients.first?.activeRole ?? AccessRole.patient.rawValue) ?? .patient
    }

    private var canViewClinicianData: Bool {
        activeRole == .clinician && patients.first?.shareWithClinician == true
    }

    private var isLoggedIn: Bool {
        !authToken.isEmpty
    }

    private var authButtonTitle: String {
        if isAuthenticating {
            return isCreatingAccount ? "Criando..." : "Entrando..."
        }

        if isLoggedIn {
            return "Sair da conta"
        }

        return isCreatingAccount ? "Criar conta" : "Entrar"
    }

    private var isAuthButtonDisabled: Bool {
        isAuthenticating || (!isLoggedIn && (loginEmail.isEmpty || loginPassword.isEmpty || (isCreatingAccount && fullName.isEmpty)))
    }

    private var isMedicationFullyTaken: Bool {
        medicationStatus == .taken
    }

    private var hasCriticalSafetyRisk: Bool {
        safetyStatus == .urgent
    }

    private var activeTriggerLabels: [String] {
        var labels: [String] = []
        if alcoholTrigger { labels.append("álcool") }
        if poorSleepTrigger { labels.append("privação de sono") }
        if stressTrigger { labels.append("estresse") }
        if conflictTrigger { labels.append("conflito") }
        if routineChangeTrigger { labels.append("mudança de rotina") }
        if menstrualTrigger { labels.append("ciclo menstrual") }
        labels.append(contentsOf: customTriggers)
        return labels
    }

    private var journalEntryWithContext: String {
        var parts: [String] = []
        if !journalEntry.isEmpty {
            parts.append(journalEntry)
        }
        parts.append("Foco de acompanhamento: \(selectedCareFocus.rawValue).")
        if !activeTriggerLabels.isEmpty {
            parts.append("Gatilhos do dia: \(activeTriggerLabels.joined(separator: ", ")).")
        }
        if !medicationName.isEmpty || !medicationDose.isEmpty || !medicationSchedule.isEmpty {
            parts.append("Medicação cadastrada: \(medicationPlanSummary).")
        }
        if !medicationChangeNote.isEmpty {
            parts.append("Mudança de medicação/dose: \(medicationChangeNote).")
        }
        if !medicationPlans.isEmpty {
            let medicationList = medicationPlans.map { $0.summary }.joined(separator: "; ")
            parts.append("Lista de medicamentos: \(medicationList).")
        }
        if !customSymptomName.isEmpty {
            parts.append("Sintoma personalizado: \(customSymptomName) \(String(format: "%.0f", customSymptomValue))/5.")
        }
        if !customSymptoms.isEmpty {
            let symptomList = customSymptoms
                .map { "\($0.name) \(String(format: "%.0f", $0.value))/5" }
                .joined(separator: "; ")
            parts.append("Sintomas personalizados: \(symptomList).")
        }
        return parts.joined(separator: "\n")
    }

    private var medicationPlanSummary: String {
        if !medicationPlans.isEmpty {
            return medicationPlans.map(\.summary).joined(separator: "; ")
        }
        return [
            medicationName.isEmpty ? nil : medicationName,
            medicationDose.isEmpty ? nil : medicationDose,
            medicationSchedule.isEmpty ? nil : medicationSchedule
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    var body: some View {
        rootWithLifecycle
            .fullScreenCover(isPresented: shouldShowOnboardingBinding) {
                onboardingFlow
            }
            // Sprint 23: haptic feedback nas ações que importam emocionalmente
            // — save bem-sucedido vibra suave, marcar Urgente alerta, abrir
            // SOS chama a atenção.
            .sensoryFeedback(.success, trigger: saveStatusMessage) { _, newValue in
                newValue.hasPrefix("Registro")
            }
            .sensoryFeedback(.warning, trigger: hasCriticalSafetyRisk) { _, newValue in
                newValue
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isShowingCrisisSheet) { _, newValue in
                newValue
            }
            .sensoryFeedback(.success, trigger: inviteStatusMessage) { _, newValue in
                newValue.contains("aceitou") || newValue.contains("agora acompanha")
            }
            .blur(radius: isPrivacyShielded ? 24 : 0)
            .overlay {
                if isPrivacyShielded {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.white)
                        Text("Tela bloqueada")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .animation(.easeOut(duration: 0.2), value: isPrivacyShielded)
            // P1-2 (UX): toast central — cada variável de status dispara
            // showToast() ao mudar, sem alterar os sites de atribuição.
            .onChange(of: saveStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("não foi possível") || msg.localizedCaseInsensitiveContains("erro")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: scaleStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("não foi possível") || msg.localizedCaseInsensitiveContains("falha")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: reportStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("não foi possível")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: loginStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("não foi possível") || msg.localizedCaseInsensitiveContains("expirada") || msg.localizedCaseInsensitiveContains("erro")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: clinicianPatientStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("entre como")
                showToast(msg, level: isErr ? .warning : .success)
            }
            .onChange(of: caregiverStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: linkedCliniciansStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha")
                showToast(msg, level: isErr ? .error : .success)
            }
            .overlay(alignment: .bottom) { toastOverlay }
    }

    @ViewBuilder
    private var rootContent: some View {
        if activeRole == .clinician {
            clinicianRoot
        } else {
            patientRoot
        }
    }

    private var rootWithSheets: some View {
        rootContent
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    settingsDashboard
                        .scrollContentBackground(.hidden)
                        .background(appBackground)
                        .navigationTitle("Configurações")
                        .toolbar {
                        // SOS continua acessível mesmo dentro de Settings.
                        // Tocar fecha Settings e abre a sheet de crise no
                        // próximo run-loop — evita stacking de sheets.
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingSettings = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    isShowingCrisisSheet = true
                                }
                            } label: {
                                Image(systemName: "cross.case.fill")
                            }
                            .tint(.red)
                            .accessibilityLabel("Apoio em crise")
                            .accessibilityHint("Fecha as configurações e abre os contatos de crise.")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") {
                                isShowingSettings = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingPasswordResetConfirm) {
                passwordResetConfirmSheet
            }
            .sheet(isPresented: $isShowingPostSavePrompt) {
                postSaveThoughtSheet
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingLoginSheet) {
                NavigationStack {
                    ScrollView {
                        loginSettingsCard
                            .padding(20)
                    }
                    .background(appBackground)
                    .navigationTitle("Entrar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fechar") { isShowingLoginSheet = false }
                        }
                    }
                    // Após login bem-sucedido, fecha a sheet automaticamente.
                    .onChange(of: authToken) { _, newValue in
                        if !newValue.isEmpty {
                            isShowingLoginSheet = false
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingCrisisSheet) {
                NavigationStack {
                    ScrollView {
                        CrisisSupportCard(
                            safetyContact: safetyContact,
                            warningSigns: safetyWarningSigns,
                            strategies: safetyStrategies
                        )
                        .padding(20)
                    }
                    .background(appBackground)
                    .navigationTitle("Apoio em crise")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") { isShowingCrisisSheet = false }
                        }
                    }
                }
            }
            .sheet(item: $caregiverEditTarget) { caregiver in
                caregiverEditSheet(for: caregiver)
            }
            .sheet(isPresented: $isShowingScales) {
                NavigationStack {
                    ScrollView {
                        scalesDashboard
                            .padding(20)
                    }
                    .background(appBackground)
                    .navigationTitle("Check-up do bem-estar")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") {
                                isShowingScales = false
                            }
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
                handleBackupImport(result)
            }
    }

    private var rootWithLifecycle: some View {
        rootWithSheets
            // Sprint E #4 + Sprint A (REG-3): id é cheap key (4 contagens). O
            // recompute interno re-compara contra o fingerprint full antes de
            // re-sortar/re-summary. Trade-off: edit de check-in passado sem
            // mudar contagem (raro com SwiftData @Model que normalmente recria
            // arrays) tem latência de uma render até o próximo `count` mudar.
            // Antes (Sonnet I3): id era o fingerprint full → O(n) por re-render.
            .task(id: storeFingerprintCheap) {
                patientStore.recompute(checkIns: checkIns, assessments: assessments, alerts: alerts, reports: reports)
            }
            .onAppear {
                prepareInitialData()
                if !authToken.isEmpty {
                    Task {
                        await loadCaregivers()
                        await syncMyBackendAlerts()
                        await loadPendingInvites()
                        await loadLinkedClinicians()
                        await loadClinicianSentInvites()
                    }
                }
            }
            .onChange(of: selectedCareFocus) { _, newValue in
                selectedScale = newValue.preferredScale
                ensureAnswers(for: selectedScale)
            }
            .onChange(of: selectedPatientPage) { _, _ in
                bodySignalInteractionCount += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .neuroFlowSessionExpired)) { _ in
                // Backend rejected the refresh token. Surface a global alert
                // and wipe every cached remote artifact so the dashboard
                // never shows the previous patient's PHI to whoever logs in
                // next on the same device.
                loginStatusMessage = "Sessão expirada. Entre novamente."
                authenticatedEmail = ""
                authenticatedName = ""
                authenticatedRole = ""
                authenticatedUserId = 0
                pendingClinicianInvites = []
                clinicianSentInvites = []
                clinicianPatients = []
                selectedRemotePatient = nil
                remoteCheckIns = []
                remoteAssessments = []
                remoteAlerts = []
                remoteReports = []
                remoteCaregivers = []
                remoteAuditLogs = []
                linkedClinicians = []
                // Sprint A: drafts encriptados ainda guardavam mood/anxiety/
                // journal/safetyContact do usuário anterior. Limpa tudo.
                clearAllLocalPHIDrafts()
                isShowingSessionExpiredAlert = true
            }
            .alert("Sessão expirada", isPresented: $isShowingSessionExpiredAlert) {
                Button("Entrar novamente") {
                    // Sprint 22: abre direto a sheet de login dedicada em vez
                    // do Settings inteiro — paciente vai pro formulário em 1
                    // toque, sem ter que rolar nada.
                    isShowingLoginSheet = true
                }
                Button("Mais tarde", role: .cancel) {}
            } message: {
                Text("Sua sessão foi encerrada por inatividade ou por uma ação no servidor. Os dados locais estão preservados. Entre novamente para voltar a sincronizar com o backend.")
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Blur sensitive PHI whenever the app is not actively focused.
                // Protects the clinician dashboard and patient diary from
                // shoulder-surfing in the app switcher and on lock screen.
                isPrivacyShielded = newPhase != .active || Self.activeScreenIsCaptured
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                // Screen recording / mirroring engages the privacy shield
                // even while the user keeps the app in the foreground.
                // Closest iOS gets to a 'no screen capture' guarantee
                // without resorting to private APIs (F23).
                if Self.activeScreenIsCaptured {
                    isPrivacyShielded = true
                } else if scenePhase == .active {
                    isPrivacyShielded = false
                }
            }
    }

    // MARK: - Onboarding (Sprint 20)

    /// Apresenta o onboarding apenas para pacientes (não para clínicos) e só
    /// enquanto a flag persistida não estiver marcada. Liga em escrita só
    /// para o getter de `isPresented`; o `set` é no-op porque o flow controla
    /// fechamento via mudança do `@AppStorage`.
    private var shouldShowOnboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding && activeRole == .patient },
            set: { _ in }
        )
    }

    @ViewBuilder
    private var onboardingFlow: some View {
        TabView(selection: $onboardingStep) {
            onboardingSlide(
                step: 0,
                icon: "heart.text.square.fill",
                tint: .red,
                title: "Bem-vindo ao NeuroFlow",
                body: "Acompanhe seu humor todos os dias com calma. O app guarda seus registros com segurança no seu aparelho e na sua conta.",
                ctaText: "Vamos lá"
            ) {
                onboardingStep = 1
            }

            onboardingSlide(
                step: 1,
                icon: "lock.shield.fill",
                tint: .green,
                title: "Você decide quem vê",
                body: "Profissionais só acompanham seus dados se você aceitar o convite. Você pode cancelar o acesso a qualquer momento.",
                ctaText: "Continuar"
            ) {
                onboardingStep = 2
            }

            onboardingCareFocus
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(appBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func onboardingSlide(
        step: Int,
        icon: String,
        tint: Color,
        title: String,
        body: String,
        ctaText: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 96))
                .foregroundStyle(tint)
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: action) {
                Text(ctaText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .tag(step)
    }

    private var onboardingCareFocus: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 72))
                .foregroundStyle(Color.neuroOrange)
            Text("Qual é o seu foco de cuidado?")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Isso ajusta as perguntas que o app faz e o que ele observa. Você pode mudar depois em Configurações.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(CareFocus.allCases) { focus in
                        Button {
                            selectedCareFocus = focus
                        } label: {
                            HStack {
                                Text(focus.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if selectedCareFocus == focus {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.neuroOrange)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        selectedCareFocus == focus ? Color.neuroOrange : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            Button {
                let patient = ensurePatient()
                patient.consentAccepted = true
                try? modelContext.save()
                hasCompletedOnboarding = true
                onboardingStep = 0
            } label: {
                Text("Começar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)

            Button("Pular") {
                hasCompletedOnboarding = true
                onboardingStep = 0
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Root containers (Sprint 19 / U1' — TabView raiz para paciente)

    // M5 (UX-P0): clínico agora tem TabView própria — antes era um único
    // scroll vertical com todos os contextos misturados (lista de pacientes,
    // análise clínica, relatórios). Cada aba tem NavigationStack própria;
    // o detalhe do paciente navega por push, não expande inline.
    @ViewBuilder
    private var clinicianRoot: some View {
        TabView(selection: $clinicianTab) {
            clinicianPatientsTab
                .tabItem { Label(ClinicianTab.patients.rawValue, systemImage: ClinicianTab.patients.icon) }
                .tag(ClinicianTab.patients)
            clinicianAnalysisTab
                .tabItem { Label(ClinicianTab.analysis.rawValue, systemImage: ClinicianTab.analysis.icon) }
                .tag(ClinicianTab.analysis)
            clinicianReportsTab
                .tabItem { Label(ClinicianTab.reports.rawValue, systemImage: ClinicianTab.reports.icon) }
                .tag(ClinicianTab.reports)
        }
        .tint(.neuroOrange)
    }

    // Aba 1: lista de pacientes + detalhe via push
    @ViewBuilder
    private var clinicianPatientsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !canViewClinicianData {
                        AccessGateCard(
                            activeRole: activeRole,
                            hasSharingConsent: patients.first?.shareWithClinician == true
                        )
                        .padding(20)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            clinicianPatientsSection
                            clinicianSentInvitesSection
                        }
                        .padding(20)
                    }
                }
            }
            .background(appBackground)
            .navigationTitle("Pacientes")
            .navigationBarTitleDisplayMode(.large)
            .privacySensitive(true)
            .toolbar { toolbarContent }
            // Push navigation para o detalhe do paciente (M5)
            .navigationDestination(for: BackendUser.self) { patient in
                clinicianPatientDetailPage(for: patient)
            }
        }
    }

    // Aba 2: análise clínica agregada
    @ViewBuilder
    private var clinicianAnalysisTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !canViewClinicianData {
                        AccessGateCard(
                            activeRole: activeRole,
                            hasSharingConsent: patients.first?.shareWithClinician == true
                        )
                    } else {
                        RiskSummaryCard(summary: summary)
                        TextRiskCard(title: "Classificação textual longitudinal", assessment: summary.textAssessment)
                        ClinicianPopulationRiskCard(signature: neuroFlowRiskSignature, alerts: activeAlerts, checkIns: sortedCheckIns, remotePatients: clinicianPatients)
                        ClinicianPreConsultInsightCard(
                            summary: summary,
                            checkIns: sortedCheckIns,
                            assessments: sortedAssessments,
                            medicationPlans: medicationPlans,
                            signature: neuroFlowRiskSignature
                        )
                        longitudinalTrendsSection
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(summary.signals, id: \.self) { signal in
                                ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: signal, description: "Sinal calculado a partir dos registros diários, escalas e análise textual.")
                            }
                        }
                        .panelStyle()
                        alertsSection
                    }
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Análise")
            .navigationBarTitleDisplayMode(.large)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    // Aba 3: relatórios
    @ViewBuilder
    private var clinicianReportsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !canViewClinicianData {
                        AccessGateCard(
                            activeRole: activeRole,
                            hasSharingConsent: patients.first?.shareWithClinician == true
                        )
                    } else {
                        reportSection
                    }
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Relatórios")
            .navigationBarTitleDisplayMode(.large)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    // Tela de detalhe do paciente — empurrada via NavigationLink (M5).
    // Carrega dados remotos ao entrar e apresenta as sub-tabs com labels.
    @ViewBuilder
    private func clinicianPatientDetailPage(for patient: BackendUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Sub-tabs com ícone + label (M5 + P1-10)
                Picker("Seção", selection: $remotePatientSubTab) {
                    ForEach(RemotePatientSubTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if !remotePatientStatusMessage.isEmpty && remotePatientStatusMessage != "Dados carregados." {
                    Text(remotePatientStatusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Group {
                    if isLoadingRemotePatientData {
                        remotePatientSkeleton
                    } else {
                        switch remotePatientSubTab {
                        case .overview:
                            RemotePatientSnapshotCard(
                                patient: patient,
                                checkIns: remoteCheckIns,
                                assessments: remoteAssessments,
                                alerts: remoteAlerts,
                                reports: remoteReports
                            )
                        case .checkIns:
                            remotePatientCheckInsList
                        case .assessments:
                            remotePatientAssessmentsList
                        case .alerts:
                            remotePatientAlertsList
                        case .reports:
                            remotePatientReportsList
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
        }
        .background(appBackground)
        .navigationTitle(patient.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .privacySensitive(true)
        .task(id: patient.id) {
            await loadRemotePatientData(patient)
        }
    }

    @ViewBuilder
    private var patientRoot: some View {
        TabView(selection: $selectedPatientPage) {
            patientTabHome
                .tabItem { Label(PatientPage.diary.rawValue, systemImage: PatientPage.diary.icon) }
                // Sprint 23: badge sinaliza convites pendentes + alertas não
                // reconhecidos sem o paciente precisar voltar à aba Hoje.
                .badge(homeTabBadgeCount)
                .tag(PatientPage.diary)

            patientTabBody
                .tabItem { Label(PatientPage.bodySignals.rawValue, systemImage: PatientPage.bodySignals.icon) }
                .tag(PatientPage.bodySignals)

            patientTabEvolution
                .tabItem { Label(PatientPage.evolution.rawValue, systemImage: PatientPage.evolution.icon) }
                .tag(PatientPage.evolution)

            patientTabTools
                .tabItem { Label(PatientPage.tools.rawValue, systemImage: PatientPage.tools.icon) }
                .tag(PatientPage.tools)
        }
        .tint(.neuroOrange)
    }

    @ViewBuilder
    private var patientTabHome: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientDashboard
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Hoje")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                // Save flutuante (Sprint 19) com consent inline (Sprint 20).
                // Se o paciente ainda não aceitou compartilhar, em vez de
                // mostrar um save cinza sem explicação, mostramos um toggle
                // claro: "Aceito compartilhar para salvar meus registros".
                Group {
                    if canSaveClinicalData {
                        Button(action: saveDailyCheckIn) {
                            Label("Salvar registro de hoje", systemImage: "tray.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityHint("Salva o registro de hoje no histórico local e sincroniza com o backend.")
                    } else if let patient = patients.first {
                        // M4 (UX-P0): antes o botão ficava desabilitado sem
                        // nenhuma explicação visível. Agora exibimos a razão
                        // do bloqueio e o toggle de consentimento lado a lado,
                        // eliminando o estado silencioso de "botão cinza".
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("Ative o consentimento para salvar seus registros.")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Toggle(isOn: Binding(
                                get: { patient.consentAccepted },
                                set: { newValue in
                                    patient.consentAccepted = newValue
                                    try? modelContext.save()
                                }
                            )) {
                                Text("Aceito acompanhar meu humor com segurança.")
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.switch)
                            .tint(.neuroOrange)
                            // Sprint A: identifier herdado da view `privacyConsent` órfã
                            // (removida nesta sprint) para o UI test seguir achando este switch.
                            .accessibilityIdentifier("privacyConsentToggle")
                            .accessibilityHint("Ao aceitar, você libera o salvamento do seu primeiro registro diário.")
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: canSaveClinicalData)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .padding(.bottom, 4)
                .background(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private var patientTabBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientBodySignalsPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Corpo")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    private var patientTabEvolution: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientEvolutionPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Evolução")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    private var patientTabTools: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientToolsPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Ferramentas")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // P1-3 (UX): troca de papel direto na toolbar, sem abrir Settings.
        // Ícone badge mostra o papel ativo — clínico vê "Médico", paciente vê
        // "Paciente". ConfirmationDialog reutiliza o mecanismo já existente.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                roleChangePending = activeRole == .clinician ? .patient : .clinician
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: activeRole == .clinician ? "stethoscope" : "person.fill")
                        .font(.subheadline)
                    Text(activeRole == .clinician ? "Médico" : "Paciente")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .tint(.primary)
            .accessibilityLabel("Perfil ativo: \(activeRole == .clinician ? "Médico" : "Paciente"). Toque para alternar.")
        }
        // Crise sempre acessível (M10) — botão vermelho próximo do polegar
        // direito em qualquer aba, abre o CrisisSupportCard na hora.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingCrisisSheet = true
            } label: {
                Image(systemName: "cross.case.fill")
            }
            .tint(.red)
            .accessibilityLabel("Apoio em crise")
            .accessibilityHint("Abre contatos do CVV, SAMU e seu contato de segurança.")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            // Cor neutra (Sprint 21) — settings é navegação secundária, não
            // ação primária. SOS continua vermelho para destacar urgência.
            .tint(.primary)
            .accessibilityLabel("Configurações")
        }
    }

    private var appBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color.neuroYellow.opacity(0.18),
                Color.orange.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: activeRole == .clinician ? "brain.head.profile" : "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(
                            colors: [.neuroYellow, .neuroGold, .neuroOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text("NeuroFlow")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(activeRole == .clinician ? "Monitoramento claro, contínuo e conectado ao cuidado." : "Um espaço simples para acompanhar seu dia e perceber padrões com mais clareza.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                StatBadge(title: "Registros", value: "\(checkIns.count)", icon: "calendar.badge.clock")
                StatBadge(title: activeRole == .clinician ? "Escalas" : "Check-ups", value: "\(assessments.count)", icon: "checklist.checked")
                StatBadge(title: activeRole == .clinician ? "Risco" : "Hoje", value: patientMoodStatus, icon: activeRole == .clinician ? "waveform.path.ecg" : "sparkles")
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // P3-2 (UX): "Ok" cobria humor 2/ansiedade 2 (clinicamente impreciso).
    // Agora 4 estados mapeiam melhor o espectro de bem-estar do paciente.
    private var patientMoodStatus: String {
        if summary.riskLevel == .high || hasCriticalSafetyRisk {
            return "Atenção"
        }
        if summary.riskLevel == .moderate {
            return "Moderado"
        }
        if mood >= 4 && anxiety <= 2 && energy >= 3 {
            return "Bem"
        }
        if mood >= 3 {
            return "Estável"
        }
        return "Difícil"
    }

    // Sprint A: a view `privacyConsent` foi removida — era órfã (zero callers
    // desde Sprint 19/20). O Toggle de consent agora vive inline no
    // safeAreaInset do diário (linhas 1446-1457) e o accessibilityIdentifier
    // "privacyConsentToggle" foi propagado pra lá para o UI test seguir verde.

    /// "Hoje" tab content — streak + banner de convites + status + diário.
    /// Sprint 23 adicionou o `streakBanner` no topo para reforço positivo.
    private var patientDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // M17/P2 (UX): banner de crise visível no TOPO quando risco é
            // alto, antes de qualquer scroll. Antes o CrisisSupportCard só
            // aparecia no final do diário — inacessível numa situação real.
            if hasCriticalSafetyRisk || currentTextAssessment.level == .high {
                Button {
                    isShowingCrisisSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cross.case.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apoio disponível agora")
                                .font(.subheadline.weight(.bold))
                            Text("Toque para ver contatos de crise e seu plano de segurança.")
                                .font(.caption)
                                .opacity(0.9)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apoio em crise disponível. Toque para abrir contatos e plano de segurança.")
            }

            if shouldShowMoodCoachmark {
                moodCoachmark
            }
            if currentCheckInStreak >= 2 {
                streakBanner
            }
            if shouldShowInvitesBanner {
                clinicianInvitesBanner
            }
            if !inviteStatusMessage.isEmpty {
                Label(inviteStatusMessage, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            patientDiaryPage
        }
    }

    /// Conteúdo da tab "Ferramentas" — Sprint 20 substituiu o scroll vertical
    /// de 7 cards por uma `List` com seções nativas + NavigationLinks. Cada
    /// item agora vive em sua própria tela, reduzindo carga cognitiva.
    private var patientToolsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tudo que apoia seu cuidado em um lugar só.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            toolsList
        }
    }

    private var toolsList: some View {
        VStack(spacing: 0) {
            toolsGroup(title: "Sua segurança", icon: "cross.case.fill", tint: .red) {
                toolRow(
                    icon: "shield.lefthalf.filled",
                    label: "Plano de segurança",
                    subtitle: "Sinais de alerta + contato de confiança",
                    destination: AnyView(
                        scrollableDetail(title: "Plano de segurança") {
                            SafetyPlanEditorCard(
                                safetyContact: $safetyContact,
                                warningSigns: $safetyWarningSigns,
                                strategies: $safetyStrategies,
                                signature: neuroFlowRiskSignature,
                                careFocus: selectedCareFocus
                            )
                        }
                    )
                )
                toolRow(
                    icon: "phone.fill.arrow.up.right",
                    label: "Apoio em crise",
                    subtitle: "CVV, SAMU e seu contato de segurança",
                    destination: AnyView(
                        scrollableDetail(title: "Apoio em crise") {
                            CrisisSupportCard(
                                safetyContact: safetyContact,
                                warningSigns: safetyWarningSigns,
                                strategies: safetyStrategies
                            )
                        }
                    )
                )
            }

            toolsGroup(title: "Acompanhamento", icon: "stethoscope", tint: .blue) {
                // M3 (UX-P0): navega diretamente ao scalesDashboard sem a
                // tela intermediária ScaleAccessCard, eliminando 1 toque extra.
                toolRowButton(
                    icon: "list.clipboard.fill",
                    label: "Check-up estruturado",
                    subtitle: "PHQ-9 · GAD-7 · YMRS (\(sortedAssessments.count) realizados)"
                ) {
                    isShowingScales = true
                }
                toolRow(
                    icon: "flame.fill",
                    label: "Engajamento",
                    subtitle: "Seu progresso no app",
                    destination: AnyView(
                        scrollableDetail(title: "Engajamento") {
                            EngagementCard(checkInCount: checkIns.count, recentCheckIns: sortedCheckIns)
                        }
                    )
                )
            }

            toolsGroup(title: "Aprender", icon: "book.fill", tint: .purple) {
                toolRow(
                    icon: "graduationcap.fill",
                    label: "Psicoeducação",
                    subtitle: "Material curado para o seu foco",
                    destination: AnyView(
                        scrollableDetail(title: "Psicoeducação") {
                            PsychoeducationCard()
                        }
                    )
                )
                toolRow(
                    icon: "questionmark.circle.fill",
                    label: "Por que pergunto isso?",
                    subtitle: "Como suas respostas alimentam o cuidado",
                    destination: AnyView(
                        scrollableDetail(title: "Por que pergunto isso?") {
                            DSM5FoundationCard(selectedFocus: selectedCareFocus)
                        }
                    )
                )
            }

            toolsGroup(title: "Compartilhar", icon: "square.and.arrow.up", tint: .green) {
                toolRow(
                    icon: "calendar.badge.clock",
                    label: "Relatório mensal automático",
                    subtitle: "Envio para sua equipe de cuidado",
                    destination: AnyView(
                        scrollableDetail(title: "Relatório mensal") {
                            MonthlyReportAutomationCard(
                                isEnabled: $autoMonthlyReportEnabled,
                                reportStatusMessage: reportStatusMessage,
                                generateReport: generateReport
                            )
                        }
                    )
                )
                toolRow(
                    icon: "doc.text.fill",
                    label: "Exportar PDF / CSV",
                    subtitle: "Levar para consulta",
                    destination: AnyView(
                        scrollableDetail(title: "Exportar relatório") {
                            PatientReportExportCard(
                                reportPreview: reportPreview,
                                pdfURL: reportPDFURL,
                                csvURL: reportCSVURL,
                                generateReport: generateReport
                            )
                        }
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func toolsGroup<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func toolRow(
        icon: String,
        label: String,
        subtitle: String,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 54)
        }
    }

    /// Variante de toolRow que executa uma ação imediata em vez de navegar
    /// para uma tela destino — usada quando a sheet já está disponível na
    /// raiz (ex.: scalesDashboard via isShowingScales). M3 (UX-P0).
    private func toolRowButton(
        icon: String,
        label: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 54)
        }
    }

    @ViewBuilder
    private func scrollableDetail<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(20)
        }
        .background(appBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Dashboard médico (Sprint 24)

    /// Filtro/ordenação da lista de pacientes vinculados.
    private var filteredClinicianPatients: [BackendUser] {
        let base = clinicianPatients.sortedByRisk
        switch clinicianPatientFilter {
        case .all:
            return base
        case .highRisk:
            return base.filter { ($0.riskScore ?? 0) >= 66 }
        case .alphabetical:
            return base.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        }
    }

    /// Convites enviados filtrados por status (todos / pendentes / aceitos / recusados).
    private var filteredSentInvites: [BackendSentInvite] {
        guard let target = sentInvitesFilter.apiStatus else { return clinicianSentInvites }
        return clinicianSentInvites.filter { $0.status == target }
    }

    /// Coachmark do primeiro check-in (Sprint 23 / J1). Mostra dica
    /// contextual logo após o onboarding até o paciente registrar o primeiro
    /// check-in OU descartar manualmente.
    private var shouldShowMoodCoachmark: Bool {
        hasCompletedOnboarding
            && !hasSeenMoodCoachmark
            && activeRole == .patient
            && checkIns.isEmpty
    }

    private var moodCoachmark: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.point.down.fill")
                .font(.title2)
                .foregroundStyle(Color.neuroOrange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Comece tocando em uma emoção")
                    .font(.subheadline.weight(.semibold))
                Text("A roda abaixo ajusta humor, ansiedade e energia juntos. Depois, salve no rodapé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                hasSeenMoodCoachmark = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dispensar dica")
        }
        .padding(12)
        .background(Color.neuroYellow.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.neuroGold.opacity(0.45), lineWidth: 1)
        )
    }

    /// Conta quantos dias consecutivos (terminando hoje ou ontem) o paciente
    /// registrou check-in. Reforço positivo discreto na tab Hoje (Sprint 23).
    private var currentCheckInStreak: Int {
        guard !sortedCheckIns.isEmpty else { return 0 }
        let calendar = Calendar.current
        var expected = calendar.startOfDay(for: Date())
        var streak = 0
        // Aceita ontem como início da janela (paciente pode estar acordando
        // antes de registrar hoje).
        if let firstDate = sortedCheckIns.first?.date,
           calendar.isDateInYesterday(firstDate) {
            expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
        }
        for checkIn in sortedCheckIns {
            let day = calendar.startOfDay(for: checkIn.date)
            if calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else if day < expected {
                break
            }
        }
        return streak
    }

    private var streakBanner: some View {
        HStack(spacing: 10) {
            Text("🔥")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(currentCheckInStreak) dias seguidos")
                    .font(.subheadline.weight(.bold))
                Text("Continue — pequenos passos contam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.neuroYellow.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Você registrou \(currentCheckInStreak) dias seguidos. Continue.")
    }

    /// Contador combinado para o badge da tab "Hoje" (Sprint 23). Soma
    /// convites pendentes (ignorando snooze — badge é discreto) com alertas
    /// clínicos não reconhecidos.
    private var homeTabBadgeCount: Int {
        let pendingInvites = pendingClinicianInvites.count
        let unackedAlerts = activeAlerts.count
        return pendingInvites + unackedAlerts
    }

    /// Banner aparece quando há convite pendente E o snooze de 24h expirou.
    /// Pacientes podem postergar pra reduzir ansiedade ambiental sem perder
    /// o convite (Sprint 21).
    private var shouldShowInvitesBanner: Bool {
        guard !pendingClinicianInvites.isEmpty else { return false }
        return Date().timeIntervalSince1970 >= inviteSnoozedUntil
    }

    private var clinicianInvitesBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label("Convites de profissional", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    inviteSnoozedUntil = Date().addingTimeInterval(24 * 3600).timeIntervalSince1970
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Decidir depois")
                .accessibilityHint("Esconde os convites por 24 horas. Eles continuam disponíveis nas configurações.")
            }

            Text("Profissionais que pediram para acompanhar você. O vínculo só é criado depois que você aceitar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(pendingClinicianInvites) { invite in
                VStack(alignment: .leading, spacing: 8) {
                    Text(invite.clinicianFullName)
                        .font(.subheadline.weight(.semibold))
                    Text(invite.clinicianEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            Task { await acceptInvite(invite) }
                        } label: {
                            Label("Aceitar", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Aceita que \(invite.clinicianFullName) acompanhe seus registros.")

                        Button(role: .destructive) {
                            Task { await revokeInvite(invite) }
                        } label: {
                            Label("Recusar", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Rejeita o convite e impede o vínculo.")
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.neuroYellow.opacity(0.18), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.neuroGold.opacity(0.35), lineWidth: 1)
        }
    }

    private var patientDiaryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "book.closed", title: "Diário")
            TodayMoodOverviewCard(
                mood: mood,
                anxiety: anxiety,
                sleepHours: sleepHours,
                medicationTaken: isMedicationFullyTaken
            )
            PatientFeedbackCard(summary: summary, canSave: canSaveClinicalData)
            OfflineSyncStatusCard(
                pendingCount: offlineSyncQueue.count,
                lastStatus: lastSyncStatus,
                retrySync: retryPendingSync
            )

            // M2 (UX-P0): diário dividido em 3 seções recolhíveis para reduzir
            // carga cognitiva. Pacientes com baixa energia podem expandir apenas
            // o que precisam preencher, sem rolar uma tela única interminável.
            VStack(alignment: .leading, spacing: 16) {

                // ── Seção 1: Como você está? ─────────────────────────────────
                DisclosureGroup(isExpanded: $diarySection1Expanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        MoodWheelCard(mood: $mood, anxiety: $anxiety, energy: $energy)

                        Text("Toque no estado que mais combina com hoje")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            // Rótulos qualitativos sem prefixo numérico — paciente
                            // pensa em "Muito difícil" / "Ótimo", não em "1" / "5".
                            VisualMetricPicker(title: "Humor", icon: "face.smiling", value: $mood, options: [
                                MetricOption(label: "Muito difícil", value: 1, color: .red),
                                MetricOption(label: "Difícil", value: 2, color: .orange),
                                MetricOption(label: "Regular", value: 3, color: .neuroYellow),
                                MetricOption(label: "Bem", value: 4, color: .green),
                                MetricOption(label: "Ótimo", value: 5, color: .green)
                            ])

                            VisualMetricPicker(title: "Ansiedade", icon: "waveform.path.ecg", value: $anxiety, options: [
                                MetricOption(label: "Tranquilo", value: 1, color: .green),
                                MetricOption(label: "Leve", value: 2, color: .green),
                                MetricOption(label: "Média", value: 3, color: .neuroYellow),
                                MetricOption(label: "Alta", value: 4, color: .orange),
                                MetricOption(label: "Pico", value: 5, color: .red)
                            ])

                            VisualMetricPicker(title: "Energia", icon: "bolt", value: $energy, options: [
                                MetricOption(label: "Exausto", value: 1, color: .red),
                                MetricOption(label: "Baixa", value: 2, color: .orange),
                                MetricOption(label: "Normal", value: 3, color: .neuroYellow),
                                MetricOption(label: "Boa", value: 4, color: .green),
                                MetricOption(label: "Alta", value: 5, color: .green)
                            ])

                            VisualMetricPicker(title: "Irritabilidade", icon: "exclamationmark.bubble", value: $irritability, options: [
                                MetricOption(label: "Calmo", value: 1, color: .green),
                                MetricOption(label: "Leve", value: 2, color: .green),
                                MetricOption(label: "Média", value: 3, color: .neuroYellow),
                                MetricOption(label: "Alta", value: 4, color: .orange),
                                MetricOption(label: "Pico", value: 5, color: .red)
                            ])

                            VisualMetricPicker(title: "Sono", icon: "moon.zzz", value: $sleepHours, options: [
                                MetricOption(label: "<4h", value: 4, color: .red),
                                MetricOption(label: "5h", value: 5, color: .orange),
                                MetricOption(label: "6h", value: 6, color: .neuroYellow),
                                MetricOption(label: "7h", value: 7, color: .green),
                                MetricOption(label: "8h+", value: 8, color: .green)
                            ], suffix: "h")

                            VisualMetricPicker(title: "Apetite", icon: "fork.knife", value: $appetite, options: [
                                MetricOption(label: "Muito baixo", value: 1, color: .red),
                                MetricOption(label: "Baixo", value: 2, color: .orange),
                                MetricOption(label: "Normal", value: 3, color: .neuroYellow),
                                MetricOption(label: "Alto", value: 4, color: .orange),
                                MetricOption(label: "Voraz", value: 5, color: .red)
                            ])

                            // P2-7 (UX): "Não se aplica" evita ruído de dados
                            // com valor default 3 para quem ignora o campo.
                            VisualMetricPicker(
                                title: "Libido", icon: "heart", value: $libido,
                                options: [
                                    MetricOption(label: "Muito baixa", value: 1, color: .red),
                                    MetricOption(label: "Baixa", value: 2, color: .orange),
                                    MetricOption(label: "Normal", value: 3, color: .neuroYellow),
                                    MetricOption(label: "Alta", value: 4, color: .orange),
                                    MetricOption(label: "Muito alta", value: 5, color: .red)
                                ],
                                skipLabel: "Não se aplica",
                                skipValue: 0.0
                            )
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Como você está?", systemImage: "face.smiling")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()

                // ── Seção 2: Segurança e medicação ───────────────────────────
                DisclosureGroup(isExpanded: $diarySection2Expanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        DailySafetyChoices(
                            medicationStatus: $medicationStatus,
                            safetyStatus: $safetyStatus
                        )

                        MedicationPlanCard(
                            medicationName: $medicationName,
                            medicationDose: $medicationDose,
                            medicationSchedule: $medicationSchedule,
                            medicationPrescription: $medicationPrescription,
                            medicationChangeNote: $medicationChangeNote,
                            medicationPlans: medicationPlans,
                            addMedication: addMedicationPlan,
                            removeMedication: removeMedicationPlan
                        )

                        CustomSymptomCard(
                            symptomName: $customSymptomName,
                            symptomValue: $customSymptomValue,
                            symptoms: customSymptoms,
                            addSymptom: addCustomSymptom,
                            removeSymptom: removeCustomSymptom
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Segurança e medicação", systemImage: "pills")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()

                // ── Seção 3: Texto livre e gatilhos ──────────────────────────
                DisclosureGroup(isExpanded: $diarySection3Expanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledTextEditor(title: "Efeitos colaterais", systemImage: "pills", placeholder: "Ex.: sonolência, náusea, agitação", text: $sideEffects)
                        LabeledTextEditor(title: "Pensamentos do dia", systemImage: "bubble.left.and.text.bubble.right", placeholder: "Ex.: pensamentos que apareceram várias vezes hoje", text: $automaticThoughts)
                        LabeledTextEditor(title: "Meu diário", systemImage: "square.and.pencil", placeholder: "Escreva como foi seu dia, sono, acontecimentos e o que quiser lembrar depois.", text: $journalEntry)
                            .onChange(of: journalEntry) { _, newValue in
                                updateTypingSignals(text: newValue)
                            }

                        TextRiskCard(title: "Sinais percebidos no diário", assessment: currentTextAssessment, patientStyle: true)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Texto livre e gatilhos", systemImage: "square.and.pencil")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                // P1-2 (UX): status de salvar migrado para o toast central.
                // O onChange(of: saveStatusMessage) no body faz o dispatch.
            }
            .panelStyle()

            TriggerMapCard(
                alcoholTrigger: $alcoholTrigger,
                poorSleepTrigger: $poorSleepTrigger,
                stressTrigger: $stressTrigger,
                conflictTrigger: $conflictTrigger,
                routineChangeTrigger: $routineChangeTrigger,
                menstrualTrigger: $menstrualTrigger,
                customTriggerText: $customTriggerText,
                customTriggers: $customTriggers,
                checkIns: sortedCheckIns
            )
            // Cards de ferramentas (SafetyPlanEditor, Engagement, Psychoeducation,
            // DSM5Foundation, ScaleAccess, MonthlyReport, ReportExport) foram
            // movidos para a tab "Ferramentas" no Sprint 19. Mantemos só
            // AutomaticWellbeingCheckup no Diário porque ele depende
            // diretamente do check-in que o paciente acabou de preencher.
            AutomaticWellbeingCheckupCard(
                results: automaticCheckupResults,
                statusMessage: scaleStatusMessage,
                canSave: canSaveClinicalData,
                save: saveAutomaticCheckups
            )

            if hasCriticalSafetyRisk || currentTextAssessment.level == .high {
                CrisisSupportCard(
                    safetyContact: safetyContact,
                    warningSigns: safetyWarningSigns,
                    strategies: safetyStrategies
                )
            }
        }
    }

    private var patientBodySignalsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "waveform.path.ecg", title: "Sinais do corpo")

            BodySignalsIntroCard()

            if !biometricConsentAccepted {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Consentimento necessário", systemImage: "hand.raised.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text("A coleta de sinais biométricos (frequência cardíaca, variabilidade de voz) requer seu consentimento específico. Esses dados são processados localmente no aparelho e não são enviados ao servidor sem sua autorização explícita.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        biometricConsentAccepted = true
                    } label: {
                        Text("Concordar e ativar sinais biométricos")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityHint("Consente com a coleta local de sinais de câmera e microfone para análise de bem-estar.")
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
            BodySignalsReadingCard(
                heartRate: ppgManager.heartRate,
                hrv: ppgManager.hrv,
                respiration: ppgManager.respiration,
                perfusion: ppgManager.perfusion,
                stress: ppgManager.stress,
                quality: ppgManager.signalQuality,
                status: ppgManager.status,
                isMeasuring: ppgManager.isMeasuring,
                start: ppgManager.start,
                stop: ppgManager.stop
            )

            // Sprint 25: detalhes técnicos colapsados por padrão. Usuários
            // curiosos podem expandir; quem só quer o essencial não é
            // sobrecarregado com jargão (latência de digitação, jitter, etc).
            DisclosureGroup(isExpanded: $isShowingBodySignalsTechnicalDetails) {
                VStack(alignment: .leading, spacing: 16) {
                    BodySignalsBehaviorCard(
                        typingLatency: bodySignalTypingLatency,
                        typingSpeed: bodySignalTypingSpeed,
                        interactionCount: bodySignalInteractionCount,
                        sessionMinutes: Date().timeIntervalSince(appSessionStartedAt) / 60,
                        voiceAverage: voiceManager.averagePower,
                        voicePauseRatio: voiceManager.pauseRatio,
                        voiceVariability: voiceManager.variability,
                        voicePitch: voiceManager.fundamentalFrequency,
                        voicePitchVariability: voiceManager.pitchVariability,
                        voiceSyllableEnergy: voiceManager.syllableEnergy,
                        voiceRhythm: voiceManager.rhythm,
                        voiceStatus: voiceManager.status,
                        isRecording: voiceManager.isRecording,
                        startVoice: voiceManager.start,
                        stopVoice: voiceManager.stop
                    )

                    CombinedBodySignalCard(
                        ppgStress: ppgManager.stress,
                        signalQuality: ppgManager.signalQuality,
                        typingSpeed: bodySignalTypingSpeed,
                        voicePauseRatio: voiceManager.pauseRatio,
                        voiceVariability: voiceManager.variability,
                        sleepHours: healthSleepHours > 0 ? healthSleepHours : sleepHours,
                        steps: healthSteps
                    )
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.neuroYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detalhes técnicos das medições")
                            .font(.subheadline.weight(.semibold))
                        Text(isShowingBodySignalsTechnicalDetails ? "Toque para esconder" : "Voz, digitação e combinação dos sinais")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Expande ou recolhe as métricas avançadas de comportamento e voz")
            }
            .panelStyle()

            BodySignalsSourcesCard(
                sleepHours: healthSleepHours,
                steps: healthSteps,
                heartRate: healthHeartRate,
                activeEnergy: healthActiveEnergy,
                syncHealth: {
                    Task {
                        await requestHealthKitAccessAndSync()
                    }
                }
            )

            BodySignalsLimitationsCard()

            Button(role: .destructive) {
                ppgManager.stop()
                voiceManager.stop()
                biometricConsentAccepted = false
            } label: {
                Label("Revogar consentimento de biossensores", systemImage: "hand.raised.slash.fill")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            } // end biometricConsentAccepted else
        }
    }

    private var patientEvolutionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "chart.line.uptrend.xyaxis", title: "Evolução")

            EvolutionSearchFilterCard(
                query: $evolutionSearchQuery,
                filter: $evolutionFilter
            )

            // P1-1 (UX): PatientFeedbackCard removido daqui — já aparece na
            // aba "Hoje". Manter nas duas abas criava duplicação confusa sem
            // distinguir "status de hoje" de "resumo da semana". O
            // NeuroFlowRiskSignatureCard já comunica o risco longitudinal.
            NeuroFlowRiskSignatureCard(signature: neuroFlowRiskSignature)
            PatientEvolutionCard(
                checkIns: sortedCheckIns,
                currentMood: mood,
                currentAnxiety: anxiety,
                currentIrritability: irritability,
                currentSleep: sleepHours
            )
            PatientPatternInsightCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                summary: summary
            )
            AppointmentEventCard(
                appointmentDate: nextAppointmentDateBinding,
                note: $nextAppointmentNote
            )
            ClinicalTimelineCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                appointmentDate: Date(timeIntervalSince1970: nextAppointmentAt),
                appointmentNote: nextAppointmentNote
            )
            DigitalPhenotypeCard(
                checkIns: sortedCheckIns,
                medicationPlans: medicationPlans,
                signature: neuroFlowRiskSignature,
                ppgStress: ppgManager.stress,
                ppgQuality: ppgManager.signalQuality,
                voicePauseRatio: voiceManager.pauseRatio,
                typingSpeed: bodySignalTypingSpeed,
                healthSleepHours: healthSleepHours,
                healthSteps: healthSteps,
                healthHeartRate: healthHeartRate
            )
            MonthlyMoodCalendarCard(checkIns: sortedCheckIns)
            YearMoodOverviewCard(checkIns: sortedCheckIns)
            MedicationTrackerCard(
                medicationStatus: medicationStatus,
                adherence: summary.medicationAdherence,
                sideEffects: sideEffects,
                checkIns: sortedCheckIns
            )
            CircadianStabilityCard(
                sleepHours: sleepHours,
                averageSleep: summary.averageSleep,
                checkInCount: summary.analyzedCheckInCount
            )
            CareFocusCard(selectedFocus: $selectedCareFocus)
            ClinicalPersonalizationCard(selectedFocus: selectedCareFocus)

            historySection
        }
    }

    private var scalesDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "heart.text.square", title: "Check-up do bem-estar")

            Picker("Escala", selection: $selectedScale) {
                ForEach(ScaleKind.allCases) { scale in
                    Text(scale.rawValue).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedScale) { _, _ in
                ensureAnswers(for: selectedScale)
                scaleStatusMessage = ""
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(selectedScale.focus)
                    .font(.headline)

                Text("Sugestão: registre \(summary.cadence.lowercased()), ajustando conforme sentir necessidade.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(selectedScale.administrationNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // P1-5 (UX): ScaleResultCard movido para depois das questões.
                // Antes o resultado ("Grave") aparecia antes de o paciente
                // responder qualquer item — ancoragem cognitiva que pode
                // influenciar as respostas. Agora o score atualiza em tempo
                // real conforme o paciente responde, e fica visível no final.
                ForEach(selectedScale.questions.indices, id: \.self) { index in
                    ScaleQuestionRow(
                        number: index + 1,
                        question: selectedScale.questions[index],
                        range: selectedScale.answerRange(for: index),
                        answer: answerBinding(for: selectedScale, index: index)
                    )
                }

                ScaleResultCard(
                    scale: selectedScale,
                    score: selectedScaleScore,
                    interpretation: selectedScaleInterpretation,
                    hasCriticalPHQ9Answer: hasCriticalPHQ9Answer
                )

                Button(action: saveScaleAssessment) {
                    Label("Salvar \(selectedScale.rawValue)", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveClinicalData)

                // P1-2: status migrado para toast central.
            }
            .panelStyle()

            recentScalesSection
        }
    }

    private var doctorDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "stethoscope", title: "Dashboard médico")

            if !canViewClinicianData {
                AccessGateCard(
                    activeRole: activeRole,
                    hasSharingConsent: patients.first?.shareWithClinician == true
                )
            } else {
                clinicianPatientsSection
                clinicianSentInvitesSection
                RiskSummaryCard(summary: summary)
                TextRiskCard(title: "Classificação textual longitudinal", assessment: summary.textAssessment)
                ClinicianPopulationRiskCard(signature: neuroFlowRiskSignature, alerts: activeAlerts, checkIns: sortedCheckIns, remotePatients: clinicianPatients)
                ClinicianPreConsultInsightCard(
                    summary: summary,
                    checkIns: sortedCheckIns,
                    assessments: sortedAssessments,
                    medicationPlans: medicationPlans,
                    signature: neuroFlowRiskSignature
                )

                longitudinalTrendsSection

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(summary.signals, id: \.self) { signal in
                        ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: signal, description: "Sinal calculado a partir dos registros diários, escalas e análise textual.")
                    }
                }
                .panelStyle()

                alertsSection
                reportSection
            }
        }
    }

    private var longitudinalTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "chart.xyaxis.line", title: "Análise longitudinal")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                TrendMetricCard(
                    title: "Humor",
                    icon: "face.smiling",
                    firstValue: summary.firstMood,
                    latestValue: summary.latestMood,
                    trend: summary.moodTrend,
                    unit: "",
                    higherIsBetter: true
                )

                TrendMetricCard(
                    title: "Ansiedade",
                    icon: "waveform.path.ecg",
                    firstValue: summary.firstAnxiety,
                    latestValue: summary.latestAnxiety,
                    trend: summary.anxietyTrend,
                    unit: "",
                    higherIsBetter: false
                )

                TrendMetricCard(
                    title: "Sono",
                    icon: "moon.zzz",
                    firstValue: summary.firstSleep,
                    latestValue: summary.latestSleep,
                    trend: summary.sleepTrend,
                    unit: "h",
                    higherIsBetter: true
                )

                StatBadge(title: "Registros analisados", value: "\(summary.analyzedCheckInCount)", icon: "calendar")
            }
        }
        .panelStyle()
    }

    private var clinicianSentInvitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "envelope.badge", title: "Convites enviados")

            // Sprint 24: filtro por status — agrupa por categoria em vez de
            // misturar pending+accepted+revoked tudo junto.
            if !clinicianSentInvites.isEmpty {
                Picker("Status", selection: $sentInvitesFilter) {
                    ForEach(SentInviteStatusFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if clinicianSentInvites.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para acompanhar seus convites." : "Quando você convidar um paciente, o status do convite aparece aqui.")
            } else if filteredSentInvites.isEmpty {
                EmptyState(text: "Nenhum convite \(sentInvitesFilter.rawValue.lowercased()).")
            } else {
                ForEach(filteredSentInvites) { invite in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: inviteStatusIcon(invite.status))
                            .foregroundStyle(inviteStatusColor(invite.status))
                            .frame(width: 28, height: 28)
                            .accessibilityLabel(inviteStatusLabel(invite.status))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(invite.patientFullName.isEmpty ? invite.patientEmail : invite.patientFullName)
                                .font(.subheadline.weight(.semibold))
                            Text(invite.patientEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(inviteStatusLabel(invite.status))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(inviteStatusColor(invite.status))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Button {
                Task { await loadClinicianSentInvites() }
            } label: {
                HStack {
                    if isLoadingClinicianSentInvites {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isLoadingClinicianSentInvites ? "Atualizando..." : "Atualizar status dos convites")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty || isLoadingClinicianSentInvites)

            if !clinicianSentInvitesFlash.isEmpty {
                Label(clinicianSentInvitesFlash, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .panelStyle()
        // Borda lateral amarela — "convites enviados, aguardando paciente"
        // (Sprint 21). Distingue do card de pacientes vinculados (verde).
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
    }

    private func inviteStatusIcon(_ status: String) -> String {
        switch status {
        case "accepted":
            "checkmark.circle.fill"
        case "revoked":
            "xmark.octagon.fill"
        default:
            "hourglass"
        }
    }

    private func inviteStatusColor(_ status: String) -> Color {
        switch status {
        case "accepted":
            .green
        case "revoked":
            .red
        default:
            .orange
        }
    }

    private func inviteStatusLabel(_ status: String) -> String {
        switch status {
        case "accepted":
            "Paciente aceitou"
        case "revoked":
            "Paciente recusou"
        case "pending":
            "Aguardando aceite"
        default:
            status.capitalized
        }
    }

    private var clinicianPatientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.2", title: "Pacientes vinculados")

            HStack(spacing: 8) {
                TextField("E-mail do paciente", text: $patientLinkEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    Task {
                        await linkPatientAndReload()
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(authToken.isEmpty || patientLinkEmail.isEmpty)
            }

            Button {
                Task {
                    await loadClinicianPatients()
                }
            } label: {
                Label("Atualizar lista", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)

            // P1-2: status migrado para toast central.

            if clinicianPatients.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para buscar pacientes." : "Quando um paciente aceitar seu convite, ele aparece aqui.")
            } else {
                // Sprint 24: Picker semântico para filtrar/ordenar a lista
                // de pacientes vinculados. Médico com muitos pacientes não
                // precisa mais rolar para encontrar alto risco.
                Picker("Filtrar", selection: $clinicianPatientFilter) {
                    ForEach(ClinicianPatientFilter.allCases) { option in
                        Label(option.rawValue, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                // M5 (UX-P0): NavigationLink(value:) empurra o detalhe como
                // push em vez de expandir inline — elimina o scroll infinito.
                ForEach(filteredClinicianPatients, id: \.id) { patient in
                    NavigationLink(value: patient) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(patient.fullName)
                                    .font(.headline)
                                Text(patient.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let riskScore = patient.riskScore {
                                    Text("Risco \(riskScore)/100\(patient.riskLevel.map { " · \($0)" } ?? "")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(riskScore >= 66 ? .red : riskScore >= 34 ? .orange : .green)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if !remotePatientStatusMessage.isEmpty {
                Text(remotePatientStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // M5 (UX-P0): detalhe do paciente removido daqui — agora é push
            // navigation via NavigationLink(value:) em clinicianPatientsTab.
        }
        .panelStyle()
    }

    /// Detalhe do paciente remoto com sub-tabs (Sprint 24).
    /// Substitui o scroll vertical único pela navegação por seções clínicas.
    @ViewBuilder
    private func remotePatientDetail(for patient: BackendUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    selectedRemotePatient = nil
                    remoteCheckIns = []
                    remoteAssessments = []
                    remoteAlerts = []
                    remoteReports = []
                } label: {
                    Label("Voltar à lista", systemImage: "chevron.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(patient.fullName)
                        .font(.subheadline.weight(.bold))
                    Text(patient.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Seção", selection: $remotePatientSubTab) {
                ForEach(RemotePatientSubTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .tag(tab)
                        .accessibilityLabel(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if isLoadingRemotePatientData {
                    remotePatientSkeleton
                } else {
                    switch remotePatientSubTab {
                    case .overview:
                        RemotePatientSnapshotCard(
                            patient: patient,
                            checkIns: remoteCheckIns,
                            assessments: remoteAssessments,
                            alerts: remoteAlerts,
                            reports: remoteReports
                        )
                    case .checkIns:
                        remotePatientCheckInsList
                    case .assessments:
                        remotePatientAssessmentsList
                    case .alerts:
                        remotePatientAlertsList
                    case .reports:
                        remotePatientReportsList
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: remotePatientSubTab)
        }
    }

    private var remotePatientSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    Circle().fill(Color.secondary.opacity(0.18)).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(height: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 60)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Carregando dados do paciente")
    }

    @ViewBuilder
    private var remotePatientCheckInsList: some View {
        if remoteCheckIns.isEmpty {
            EmptyState(text: "Sem check-ins recentes.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteCheckIns) { checkIn in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkIn.createdAt.prefix(10))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            Text("Humor \(Int(checkIn.mood))")
                            Text("Ansiedade \(Int(checkIn.anxiety))")
                            Text("Sono \(checkIn.sleepHours, specifier: "%.1f")h")
                        }
                        .font(.caption2)
                        if !checkIn.journalEntry.isEmpty {
                            Text(checkIn.journalEntry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var remotePatientAssessmentsList: some View {
        if remoteAssessments.isEmpty {
            EmptyState(text: "Sem escalas aplicadas.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteAssessments) { assessment in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assessment.scaleName)
                                .font(.subheadline.weight(.semibold))
                            Text(assessment.interpretation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(assessment.score) pts")
                            .font(.headline)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var remotePatientAlertsList: some View {
        if remoteAlerts.isEmpty {
            EmptyState(text: "Sem alertas registrados.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteAlerts) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: alert.acknowledged ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(alert.level == "high" ? .red : alert.acknowledged ? .green : .orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                            Text(alert.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var remotePatientReportsList: some View {
        if remoteReports.isEmpty {
            EmptyState(text: "Sem relatórios gerados.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteReports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(report.createdAt.prefix(10))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(report.riskLevel.capitalized)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(report.riskLevel == "high" ? .red : report.riskLevel == "moderate" ? .orange : .green)
                        }
                        Text(report.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    /// Settings nativo (Sprint 21) — Form com Sections + NavigationLinks.
    /// Cada item antes empilhado vira uma sub-tela navegável. Reduz 13 cards
    /// num scroll a 6 grupos hierárquicos no padrão iOS.
    private var settingsDashboard: some View {
        Form {
            Section("Conta") {
                settingsNavLink(
                    icon: "person.crop.circle.fill",
                    tint: .blue,
                    label: isLoggedIn ? "Login e perfil" : "Entrar na conta",
                    subtitle: authenticatedEmail.isEmpty ? "Não autenticado" : authenticatedEmail
                ) {
                    scrollableDetail(title: "Conta") { loginSettingsCard }
                }

                Button {
                    // Sprint 23: paciente que pulou o onboarding ganha um
                    // caminho de volta. Marca a flag como falsa — o
                    // fullScreenCover dispara no próximo render.
                    hasCompletedOnboarding = false
                    onboardingStep = 0
                    isShowingSettings = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Refazer apresentação")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("Veja as boas-vindas e ajuste seu foco de cuidado.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                settingsNavLink(
                    icon: "person.text.rectangle.fill",
                    tint: .indigo,
                    label: "Perfil de acesso",
                    subtitle: activeRole == .clinician ? "Médico" : "Paciente"
                ) {
                    scrollableDetail(title: "Perfil de acesso") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Perfil de acesso", selection: roleBinding) {
                                ForEach(AccessRole.allCases) { role in
                                    Label(role.rawValue, systemImage: role.icon).tag(role)
                                }
                            }
                            .pickerStyle(.segmented)
                            // Sprint A: confirmation dialog antes de aplicar.
                            .confirmationDialog(
                                roleChangePending == .clinician
                                    ? "Trocar para perfil médico?"
                                    : "Trocar para perfil paciente?",
                                isPresented: Binding(
                                    get: { roleChangePending != nil },
                                    set: { if !$0 { roleChangePending = nil } }
                                ),
                                titleVisibility: .visible
                            ) {
                                Button(roleChangePending == .clinician ? "Alternar para médico" : "Alternar para paciente") {
                                    if let pending = roleChangePending {
                                        applyRoleChange(pending)
                                    }
                                    roleChangePending = nil
                                }
                                Button("Cancelar", role: .cancel) { roleChangePending = nil }
                            } message: {
                                Text("A troca muda o dashboard ativo e os dados visíveis. Você pode reverter a qualquer momento.")
                            }

                            PrivacyStatusGrid(
                                consentAccepted: patients.first?.consentAccepted == true,
                                shareWithClinician: patients.first?.shareWithClinician == true,
                                shareWithCaregiver: shareWithCaregiver,
                                activeRole: activeRole
                            )
                        }
                        .panelStyle()
                    }
                }
            }

            Section("Privacidade e dados") {
                settingsNavLink(
                    icon: "lock.shield.fill",
                    tint: .red,
                    label: "Meus dados (LGPD)",
                    subtitle: "Exportar, apagar, ver auditoria"
                ) {
                    scrollableDetail(title: "Privacidade e dados") { privacyAndDataCard }
                }

                // P2-2 (UX): seção renomeada de "Compliance" para
                // "Segurança e privacidade" com linguagem acessível para
                // pacientes e clínicos, sem jargão técnico de infraestrutura.
                settingsNavLink(
                    icon: "lock.shield",
                    tint: .blue,
                    label: "Segurança e privacidade",
                    subtitle: "Como seus dados são protegidos"
                ) {
                    scrollableDetail(title: "Segurança e privacidade") {
                        VStack(alignment: .leading, spacing: 14) {
                            ComplianceRow(icon: "person.badge.key", title: "Acesso seguro", description: "Suas credenciais nunca ficam salvas em texto puro. A sessão expira automaticamente e pode ser encerrada a qualquer momento.")
                            ComplianceRow(icon: "checkmark.seal", title: "Você decide o que compartilha", description: "O app bloqueia o salvamento até que você aceite expressamente. Autorizar o registro é independente de autorizar o compartilhamento com seu médico.")
                            ComplianceRow(icon: "lock.doc", title: "Dados criptografados no dispositivo", description: "Textos sensíveis (diário, pensamentos, efeitos colaterais) são criptografados antes de serem armazenados no seu aparelho.")
                            ComplianceRow(icon: "eye.slash", title: "Acesso do seu médico é controlado", description: "Seu médico só consegue ver seus dados após você aceitar o convite. Você pode revogar esse acesso a qualquer momento em Configurações → Profissionais com acesso.")
                            ComplianceRow(icon: "doc.text", title: "Lei Geral de Proteção de Dados (LGPD)", description: "Você pode exportar todos os seus dados ou solicitar a exclusão da conta a qualquer momento em Configurações → Privacidade e dados.")
                        }
                        .panelStyle()
                    }
                }
            }

            Section("Pessoas") {
                settingsNavLink(
                    icon: "stethoscope",
                    tint: .green,
                    label: "Profissionais com acesso",
                    subtitle: linkedClinicians.isEmpty ? "Nenhum vínculo ativo" : "\(linkedClinicians.count) profissionais"
                ) {
                    scrollableDetail(title: "Profissionais") { linkedCliniciansCard }
                }

                settingsNavLink(
                    icon: "person.2.fill",
                    tint: .blue,
                    label: "Cuidadores",
                    subtitle: remoteCaregivers.isEmpty ? "Nenhum cadastrado" : "\(remoteCaregivers.count) cadastrados"
                ) {
                    scrollableDetail(title: "Cuidadores") { caregiverManagementCard }
                }
            }

            Section("Notificações") {
                settingsNavLink(
                    icon: "bell.badge.fill",
                    tint: .orange,
                    label: "Lembretes diários",
                    subtitle: nil
                ) {
                    scrollableDetail(title: "Lembretes") { reminderSettingsCard }
                }

                settingsNavLink(
                    icon: "antenna.radiowaves.left.and.right",
                    tint: .purple,
                    label: "Push remoto",
                    subtitle: remotePushStatus
                ) {
                    scrollableDetail(title: "Push remoto") {
                        RemotePushCard(
                            isEnabled: $remotePushEnabled,
                            status: remotePushStatus,
                            token: apnsDeviceToken,
                            register: { Task { await requestRemotePushRegistration() } },
                            uploadToken: { Task { await uploadPushTokenToBackend() } }
                        )
                    }
                }
            }

            Section("Integrações") {
                settingsNavLink(
                    icon: "heart.fill",
                    tint: .pink,
                    label: "Apple Health",
                    subtitle: healthKitStatus
                ) {
                    scrollableDetail(title: "Apple Health") {
                        HealthKitIntegrationCard(
                            isEnabled: $healthKitEnabled,
                            status: healthKitStatus,
                            sleepHours: healthSleepHours,
                            steps: healthSteps,
                            heartRate: healthHeartRate,
                            activeEnergy: healthActiveEnergy,
                            sync: { Task { await requestHealthKitAccessAndSync() } }
                        )
                    }
                }

                settingsNavLink(
                    icon: "externaldrive.fill",
                    tint: .gray,
                    label: "Backup local",
                    subtitle: backgroundBackupStatus
                ) {
                    scrollableDetail(title: "Backup local") {
                        BackupExportCard(
                            backupURL: backupURL,
                            isAutomatic: $autoBackupEnabled,
                            intervalDays: $backupIntervalDays,
                            lastAutomaticBackupAt: lastAutomaticBackupAt,
                            backupStatus: loginStatusMessage,
                            backgroundStatus: backgroundBackupStatus,
                            makeBackup: { makeBackupExport() },
                            restoreBackup: { isImportingBackup = true }
                        )
                    }
                }

                settingsNavLink(
                    icon: "envelope.arrow.triangle.branch.fill",
                    tint: .teal,
                    label: "Equipe de cuidado",
                    subtitle: careTeamSendStatus
                ) {
                    scrollableDetail(title: "Equipe de cuidado") {
                        CareTeamAutoSendCard(
                            isEnabled: $autoCareTeamSendEnabled,
                            contact: $careTeamContact,
                            caregiverName: $caregiverName,
                            caregiverRelationship: $caregiverRelationship,
                            canShare: patients.first?.consentAccepted == true && (patients.first?.shareWithClinician == true || shareWithCaregiver),
                            canShareCaregiver: patients.first?.consentAccepted == true && shareWithCaregiver,
                            status: careTeamSendStatus,
                            caregivers: remoteCaregivers,
                            saveCaregiver: { Task { await saveCaregiverContact() } },
                            refreshCaregivers: { Task { await loadCaregivers() } },
                            sendNow: sendCurrentReportToCareTeam
                        )
                    }
                }
            }

            #if DEBUG
            Section("Diagnóstico interno") {
                NavigationLink("Status de produção") {
                    scrollableDetail(title: "Status de produção") { ProductionReadinessCard() }
                }
                NavigationLink("Validação clínica") {
                    scrollableDetail(title: "Validação clínica") { ClinicalValidationRoadmapCard() }
                }
            }
            #endif
        }
    }

    /// Linha padrão de Settings — ícone colorido com tint + label + subtítulo.
    /// Cor da bolinha distingue grupos sem precisar ler.
    @ViewBuilder
    private func settingsNavLink<Destination: View>(
        icon: String,
        tint: Color,
        label: String,
        subtitle: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var privacyAndDataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "lock.shield", title: "Privacidade e dados (LGPD)")

            Text("Direitos do titular: exportar tudo que está armazenado, apagar registros antigos ou encerrar sua conta. Estas ações usam endpoints autenticados do backend.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !privacyStatusMessage.isEmpty {
                Label(privacyStatusMessage, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await exportMyAccount() }
            } label: {
                Label("Baixar meus dados (JSON)", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)
            .accessibilityHint("Solicita ao backend uma exportação completa da sua conta em JSON.")

            if let exportURL = privacyExportURL {
                ShareLink(item: exportURL) {
                    Label("Compartilhar exportação", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // Picker semântico no lugar do Stepper (Sprint 21) — paciente
            // pensa em "1 ano" ou "6 meses", não em "1290 dias".
            // P2-11 (UX): label sem reticências + valor selecionado visível.
            Picker("Retenção de dados", selection: $privacyRetentionDays) {
                Text("90 dias").tag(90)
                Text("6 meses").tag(180)
                Text("1 ano").tag(365)
                Text("2 anos").tag(730)
                Text("5 anos").tag(1825)
            }
            .pickerStyle(.menu)
            .accessibilityHint("Define a janela mantida no backend. Registros mais antigos podem ser apagados pelo botão abaixo.")

            Button(role: .destructive) {
                isConfirmingClinicalWipe = true
            } label: {
                Label("Apagar dados clínicos antigos", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)
            .accessibilityHint("Remove do backend registros com mais de \(privacyRetentionDays) dias.")

            Button {
                Task { await fetchAuditLogs() }
            } label: {
                Label("Ver minha auditoria", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)

            Divider()

            // LGPD Art. 9 § 1 — consentimento para dados biométricos deve ser
            // destacado, específico e revogável a qualquer momento.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sinais biométricos (câmera e voz)")
                        .font(.subheadline.weight(.semibold))
                    Text(biometricConsentAccepted ? "Consentimento ativo — processamento local." : "Consentimento não concedido.")
                        .font(.caption)
                        .foregroundStyle(biometricConsentAccepted ? .green : .secondary)
                }
                Spacer()
                if biometricConsentAccepted {
                    Button(role: .destructive) {
                        ppgManager.stop()
                        voiceManager.stop()
                        biometricConsentAccepted = false
                    } label: {
                        Text("Revogar")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .accessibilityElement(children: .combine)

            Button(role: .destructive) {
                isConfirmingAccountDelete = true
            } label: {
                Label("Apagar minha conta", systemImage: "person.crop.circle.badge.xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(authToken.isEmpty)
            .accessibilityHint("Remove conta, vínculos médicos, alertas, relatórios e tokens do backend.")
        }
        .panelStyle()
        .alert("Apagar dados clínicos antigos?", isPresented: $isConfirmingClinicalWipe) {
            Button("Apagar", role: .destructive) {
                Task { await deleteOldClinicalData() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Apaga do backend todos os check-ins, escalas, alertas e relatórios com mais de \(privacyRetentionDays) dias. Os dados locais no aparelho permanecem.")
        }
        .alert("Apagar minha conta definitivamente?", isPresented: $isConfirmingAccountDelete) {
            Button("Apagar minha conta", role: .destructive) {
                Task { await deleteMyAccount() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação remove conta, vínculos clínicos, alertas, relatórios, tokens e cuidadores no backend. Não pode ser desfeita.")
        }
        .sheet(isPresented: $isShowingAuditLogs) {
            NavigationStack {
                List(remoteAuditLogs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.action)
                            .font(.subheadline.weight(.semibold))
                        Text("\(log.resourceType) · \(log.resourceId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(log.createdAt)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .navigationTitle("Minha auditoria")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("OK") { isShowingAuditLogs = false }
                    }
                }
            }
        }
    }

    private var linkedCliniciansCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "stethoscope", title: "Profissionais com acesso")

            Text("Profissionais que aceitaram acompanhar você. Você pode cancelar o acesso a qualquer momento.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if linkedClinicians.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para ver quem acompanha você." : "Ninguém está acompanhando você no momento. Quando aceitar um convite, o profissional aparece aqui.")
            } else {
                ForEach(linkedClinicians) { clinician in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.fill.checkmark")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(clinician.clinicianFullName)
                                .font(.subheadline.weight(.semibold))
                            Text(clinician.clinicianEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            clinicianToRevoke = clinician
                        } label: {
                            Label("Cancelar acesso", systemImage: "xmark.shield")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Cancelar acesso de \(clinician.clinicianFullName)")
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // P1-2: status migrado para toast central.
        }
        .panelStyle()
        // Borda lateral verde — "médico já tem acesso ativo aos meus dados".
        // Sprint 21: diferenciação visual contra cards de cuidadores e
        // convites enviados.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
        .alert(
            "Cancelar acesso?",
            isPresented: Binding(
                get: { clinicianToRevoke != nil },
                set: { if !$0 { clinicianToRevoke = nil } }
            ),
            presenting: clinicianToRevoke
        ) { clinician in
            Button("Cancelar acesso", role: .destructive) {
                Task { await revokeClinicalAccess(clinician) }
                clinicianToRevoke = nil
            }
            Button("Manter", role: .cancel) {
                clinicianToRevoke = nil
            }
        } message: { clinician in
            Text("\(clinician.clinicianFullName) perderá acesso aos seus check-ins, escalas e alertas. Você pode aceitar um novo convite no futuro.")
        }
    }

    private var caregiverManagementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.2.gobackward", title: "Cuidadores cadastrados")

            if remoteCaregivers.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para convidar pessoas de confiança." : "Você pode adicionar alguém de confiança que receberá alertas se algo precisar de atenção.")
            } else {
                ForEach(remoteCaregivers) { caregiver in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: caregiver.shareEnabled ? "checkmark.shield.fill" : "shield.slash")
                            .foregroundStyle(caregiver.shareEnabled ? .green : .secondary)
                            .accessibilityLabel(caregiver.shareEnabled ? "Compartilhamento ativo" : "Compartilhamento desativado")

                        VStack(alignment: .leading, spacing: 4) {
                            Text(caregiver.name)
                                .font(.subheadline.weight(.semibold))
                            Text(caregiver.contact)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !caregiver.relationship.isEmpty {
                                Text(caregiver.relationship)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Button {
                            beginEditingCaregiver(caregiver)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Editar dados de \(caregiver.name)")

                        Button(role: .destructive) {
                            Task { await deleteCaregiver(caregiver) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remover cuidador \(caregiver.name)")

                        Button {
                            Task { await toggleCaregiverSharing(caregiver) }
                        } label: {
                            Image(systemName: caregiver.shareEnabled ? "bell.slash" : "bell")
                        }
                        .accessibilityLabel(caregiver.shareEnabled ? "Pausar notificações para \(caregiver.name)" : "Reativar notificações para \(caregiver.name)")
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // P1-2: status migrado para toast central.
        }
        .panelStyle()
        // Borda lateral azul — "cuidador/rede de apoio com permissão de
        // alertas" (Sprint 21).
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
    }

    private var reminderSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "bell.badge", title: "Lembretes")

            Toggle("Lembrar medicação", isOn: $medicationReminderEnabled)
                .toggleStyle(.switch)

            // P1-7 (UX): Stepper substituído por DatePicker — era preciso até
            // 23 toques para mudar o horário. Com o DatePicker basta um gesto.
            DatePicker(
                "Horário da medicação",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: medicationReminderHour, minute: 0, second: 0, of: Date()
                        ) ?? Date()
                    },
                    set: { medicationReminderHour = Calendar.current.component(.hour, from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .disabled(!medicationReminderEnabled)

            Toggle("Lembrar check-in diário", isOn: $checkInReminderEnabled)
                .toggleStyle(.switch)

            DatePicker(
                "Horário do check-in",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: checkInReminderHour, minute: 0, second: 0, of: Date()
                        ) ?? Date()
                    },
                    set: { checkInReminderHour = Calendar.current.component(.hour, from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .disabled(!checkInReminderEnabled)

            Button {
                Task {
                    await configureLocalReminders()
                }
            } label: {
                Label("Salvar lembretes no iPhone", systemImage: "bell.and.waves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("As notificações são locais do aparelho. Push remoto exigiria APNs/Firebase e servidor em produção.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var loginSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(isLoggedIn ? .white : .black)
                    .frame(width: 44, height: 44)
                    .background(isLoggedIn ? Color.green : Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoggedIn ? "Conta conectada" : isCreatingAccount ? "Criar conta" : "Entrar na conta")
                        .font(.headline)

                    Text(isLoggedIn ? "\(authenticatedName) • \(authenticatedEmail)" : "Entre para sincronizar seus dados com segurança.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            VStack(spacing: 10) {
                if isCreatingAccount {
                    TextField("Nome completo", text: $fullName)
                        .textContentType(.name)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                TextField("E-mail", text: $loginEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                SecureField("Senha", text: $loginPassword)
                    .textContentType(.password)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // P3-1 (UX): botão de logout separado visualmente do de login —
            // antes usavam o mesmo .borderedProminent e ficavam no mesmo lugar,
            // risco de logout acidental (ação que limpa a sessão local).
            if isLoggedIn {
                Divider()
                Button(role: .destructive) {
                    Task { await handleAuthenticationButton() }
                } label: {
                    Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button {
                    Task { await handleAuthenticationButton() }
                } label: {
                    Label(authButtonTitle, systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthButtonDisabled)
            }

            if !isLoggedIn {
                HStack(spacing: 8) {
                    Button {
                        isCreatingAccount.toggle()
                        loginStatusMessage = ""
                    } label: {
                        Text(isCreatingAccount ? "Já tenho conta" : "Criar nova conta")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await requestPasswordReset()
                        }
                    } label: {
                        Text(isRequestingPasswordReset ? "Enviando..." : "Esqueci a senha")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(loginEmail.isEmpty || isRequestingPasswordReset)
                }

                Button {
                    passwordResetStatusMessage = ""
                    isShowingPasswordResetConfirm = true
                } label: {
                    Label("Tenho um código de recuperação", systemImage: "key.horizontal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(loginEmail.isEmpty)
                .accessibilityHint("Abre o formulário para enviar o código recebido por e-mail e definir uma nova senha.")
            }

            // P1-2: loginStatusMessage migrado para toast central.
            // P2-1 (UX): URL do backend e instrução de infraestrutura
            // removidas da UI de produção — expor detalhes técnicos prejudica
            // a confiança do usuário. Visível apenas em builds de Debug.
            #if DEBUG
            Text("Debug: conectando em http://127.0.0.1:8000")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            #endif
        }
        .panelStyle()
    }

    // Sprint 25: histórico passa a respeitar `evolutionFilter` + `evolutionSearchQuery`.
    // O filtro decide quais coleções aparecem; a busca recorta dentro de cada uma.
    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "clock.arrow.circlepath", title: historySectionTitle)

            if historyHasAnyVisibleContent {
                if evolutionFilter == .all || evolutionFilter == .checkIns {
                    historyCheckInsGroup
                }
                if evolutionFilter == .all || evolutionFilter == .scales {
                    historyScalesGroup
                }
                if evolutionFilter == .all || evolutionFilter == .alerts {
                    historyAlertsGroup
                }
            } else {
                // P2-3 (UX): empty state com ação direta para o diário
                // quando ainda não há registros — elimina o dead-end
                // "leva menos de 1 minuto" sem caminho para começar.
                EmptyState(
                    text: historyEmptyMessage,
                    actionLabel: evolutionFilter == .all && checkIns.isEmpty ? "Fazer primeiro registro" : nil,
                    action: evolutionFilter == .all && checkIns.isEmpty
                        ? { selectedPatientPage = .diary }
                        : nil
                )
            }
        }
    }

    private var historySectionTitle: String {
        switch evolutionFilter {
        case .all: "Histórico recente"
        case .checkIns: "Check-ins recentes"
        case .scales: "Escalas recentes"
        case .alerts: "Alertas recentes"
        }
    }

    private var historyEmptyMessage: String {
        if !evolutionQueryNormalized.isEmpty {
            return "Nenhum registro corresponde a “\(evolutionSearchQuery)”. Limpe a busca ou tente outro termo."
        }
        switch evolutionFilter {
        case .all: return "Seu primeiro check-in vai aparecer aqui. Leva menos de 1 minuto."
        case .checkIns: return "Nenhum check-in registrado ainda."
        case .scales: return "Nenhuma escala (PHQ-9, GAD-7, YMRS) respondida ainda."
        case .alerts: return "Sem alertas pendentes — tudo tranquilo por aqui."
        }
    }

    private var historyHasAnyVisibleContent: Bool {
        switch evolutionFilter {
        case .all:
            return !filteredCheckIns.isEmpty || !filteredAssessments.isEmpty || !filteredActiveAlerts.isEmpty
        case .checkIns: return !filteredCheckIns.isEmpty
        case .scales: return !filteredAssessments.isEmpty
        case .alerts: return !filteredActiveAlerts.isEmpty
        }
    }

    @ViewBuilder
    private var historyCheckInsGroup: some View {
        if !filteredCheckIns.isEmpty {
            ForEach(filteredCheckIns.prefix(evolutionFilter == .checkIns ? 20 : 5)) { checkIn in
                CheckInRow(checkIn: checkIn)
            }
        }
    }

    @ViewBuilder
    private var historyScalesGroup: some View {
        if !filteredAssessments.isEmpty {
            ForEach(filteredAssessments.prefix(evolutionFilter == .scales ? 20 : 4)) { assessment in
                AssessmentRow(assessment: assessment)
            }
        }
    }

    @ViewBuilder
    private var historyAlertsGroup: some View {
        if !filteredActiveAlerts.isEmpty {
            ForEach(filteredActiveAlerts.prefix(evolutionFilter == .alerts ? 20 : 3)) { alert in
                AlertRow(alert: alert) {
                    alert.acknowledged = true
                    try? modelContext.save()
                }
            }
        }
    }

    private var recentScalesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "list.clipboard", title: "Resultados recentes")

            if sortedAssessments.isEmpty {
                EmptyState(text: "Quando você responder PHQ-9, GAD-7 ou YMRS, a evolução das pontuações fica aqui.")
            } else {
                ForEach(sortedAssessments.prefix(6)) { assessment in
                    AssessmentRow(assessment: assessment)
                }
            }
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bell.badge", title: "Alertas acionáveis")

            if activeAlerts.isEmpty {
                EmptyState(text: "Tudo tranquilo por aqui. Continue acompanhando — alertas aparecem quando algo merece atenção.")
            } else {
                ForEach(activeAlerts) { alert in
                    AlertRow(alert: alert) {
                        alert.acknowledged = true
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "doc.text.magnifyingglass", title: "Relatórios")

            Button(action: generateReport) {
                Label("Gerar relatório clínico", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sortedCheckIns.isEmpty && sortedAssessments.isEmpty)

            if !reportPreview.isEmpty {
                Text(reportPreview)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                ShareLink(item: reportPreview) {
                    Label("Compartilhar relatório", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // P1-2: reportStatusMessage migrado para toast central.
            }

            ForEach(latestReports.prefix(3)) { report in
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Risco: \(report.riskLevel)")
                        .font(.headline)

                    Text(report.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                .panelStyle()
            }
        }
    }

    private var canSaveClinicalData: Bool {
        patients.first?.consentAccepted == true
    }

    private var hasCriticalPHQ9Answer: Bool {
        selectedScale == .phq9 && selectedScaleAnswers.indices.contains(8) && selectedScaleAnswers[8] > 0
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { patients.first?.consentAccepted ?? false },
            set: { newValue in
                let patient = ensurePatient()
                patient.consentAccepted = newValue
                if !newValue {
                    patient.shareWithClinician = false
                }
            }
        )
    }

    private var shareWithClinicianBinding: Binding<Bool> {
        Binding(
            get: { patients.first?.shareWithClinician ?? false },
            set: { newValue in
                let patient = ensurePatient()
                patient.shareWithClinician = newValue && patient.consentAccepted
            }
        )
    }

    // Sprint A: agora o setter pede confirmação antes de aplicar (toque
    // acidental no segmented picker antes trocava silenciosamente para perfil
    // médico e a TabView raiz sumia). Também adicionado `try? modelContext.save()`
    // que o setter original esquecia — SwiftData auto-save podia não persistir
    // antes de crash, perdendo a troca.
    private var roleBinding: Binding<AccessRole> {
        Binding(
            get: { activeRole },
            set: { newValue in
                if newValue != activeRole {
                    roleChangePending = newValue
                }
            }
        )
    }

    private func applyRoleChange(_ role: AccessRole) {
        let patient = ensurePatient()
        patient.activeRole = role.rawValue
        try? modelContext.save()
    }

    private func prepareInitialData() {
        // Surface any store-recovery message produced during app init.
        if let msg = NeuroFlowApp.storeRecoveryMessage {
            saveStatusMessage = msg
            NeuroFlowApp.storeRecoveryMessage = nil
        }
        _ = ensurePatient()
        ensureAnswers(for: selectedScale)
        loadMedicationPlans()
        loadCustomSymptoms()
        loadOfflineSyncQueue()
        startNetworkMonitor()
        if autoBackupEnabled && backupURL == nil
            && FileManager.default.fileExists(atPath: BackupStore.protectedFileURL.path) {
            backupURL = BackupStore.protectedFileURL
        }
        runRecurringBackupIfNeeded()
        retryPendingSync()
        if loginEmail.isEmpty {
            loginEmail = authenticatedEmail
        }
    }

    private func loadMedicationPlans() {
        guard !medicationPlansData.isEmpty, let data = medicationPlansData.data(using: .utf8) else {
            return
        }

        medicationPlans = (try? JSONDecoder().decode([MedicationPlanEntry].self, from: data)) ?? []
    }

    private func persistMedicationPlans() {
        guard let data = try? JSONEncoder().encode(medicationPlans),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        medicationPlansData = json
    }

    private func addMedicationPlan() {
        let trimmedName = medicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let entry = MedicationPlanEntry(
            name: trimmedName,
            dose: medicationDose.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: medicationSchedule.trimmingCharacters(in: .whitespacesAndNewlines),
            prescription: medicationPrescription.trimmingCharacters(in: .whitespacesAndNewlines),
            changeNote: medicationChangeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        medicationPlans.insert(entry, at: 0)
        persistMedicationPlans()
        medicationName = ""
        medicationDose = ""
        medicationSchedule = ""
        medicationPrescription = ""
        medicationChangeNote = ""
    }

    private func removeMedicationPlan(_ entry: MedicationPlanEntry) {
        medicationPlans.removeAll { $0.id == entry.id }
        persistMedicationPlans()
    }

    private func loadCustomSymptoms() {
        guard !customSymptomsData.isEmpty, let data = customSymptomsData.data(using: .utf8) else {
            return
        }

        customSymptoms = (try? JSONDecoder().decode([CustomSymptomEntry].self, from: data)) ?? []
    }

    private func persistCustomSymptoms() {
        guard let data = try? JSONEncoder().encode(customSymptoms),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        customSymptomsData = json
    }

    private func addCustomSymptom() {
        let trimmedName = customSymptomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        customSymptoms.insert(CustomSymptomEntry(name: trimmedName, value: customSymptomValue), at: 0)
        persistCustomSymptoms()
        customSymptomName = ""
        customSymptomValue = 3
    }

    private func removeCustomSymptom(_ entry: CustomSymptomEntry) {
        customSymptoms.removeAll { $0.id == entry.id }
        persistCustomSymptoms()
    }

    // N-I2: start a persistent NWPathMonitor that flushes the offline sync
    // queue whenever the network path becomes satisfied. Cancels any previous
    // monitor to avoid double-firing on hot reloads.
    private func startNetworkMonitor() {
        networkMonitor.cancel()
        networkMonitor = NWPathMonitor()
        networkMonitor.pathUpdateHandler = { [self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { retryPendingSync() }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func loadOfflineSyncQueue() {
        guard !offlineSyncQueueData.isEmpty, let data = offlineSyncQueueData.data(using: .utf8) else {
            return
        }

        offlineSyncQueue = (try? JSONDecoder().decode([OfflineSyncItem].self, from: data)) ?? []
    }

    private func persistOfflineSyncQueue() {
        guard let data = try? JSONEncoder().encode(offlineSyncQueue),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        offlineSyncQueueData = json
    }

    @discardableResult
    private func ensurePatient() -> PatientProfile {
        if let patient = patients.first {
            return patient
        }

        let patient = PatientProfile()
        modelContext.insert(patient)
        return patient
    }

    private func ensureAnswers(for scale: ScaleKind) {
        if scaleAnswers[scale]?.count != scale.questions.count {
            scaleAnswers[scale] = Array(repeating: 0, count: scale.questions.count)
        }
    }

    private func answerBinding(for scale: ScaleKind, index: Int) -> Binding<Int> {
        Binding(
            get: {
                scaleAnswers[scale, default: Array(repeating: 0, count: scale.questions.count)][index]
            },
            set: { newValue in
                ensureAnswers(for: scale)
                scaleAnswers[scale]?[index] = newValue
            }
        )
    }

    // P1-2 (UX): ponto único de exibição de feedback ao usuário.
    // Substitui as 9+ variáveis de status espalhadas por chamadas a esta
    // função. Erros não fazem auto-dismiss; confirmações somem em 2 s;
    // avisos somem em 4 s.
    private func showToast(_ message: String, level: ToastLevel = .success) {
        toastTask?.cancel()
        toastMessage = message
        toastLevel = level
        if let delay = level.autoDismissSeconds {
            toastTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                if !Task.isCancelled {
                    toastMessage = ""
                }
            }
        }
    }

    /// View que renderiza o toast sobre o conteúdo principal.
    @ViewBuilder
    private var toastOverlay: some View {
        if !toastMessage.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: toastLevel.icon)
                        .foregroundStyle(.white)
                    Text(toastMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if toastLevel == .error {
                        Button {
                            toastMessage = ""
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white.opacity(0.8))
                                .font(.caption.weight(.bold))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(toastLevel.color, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 100) // acima da TabBar
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
            .zIndex(999)
            .accessibilityLabel(toastMessage)
        }
    }

    private func saveDailyCheckIn() {
        // Sprint A (NEW-2): debounce contra double-tap. M5 colocou
        // @Attribute(.unique) dayKey em DailyCheckIn — duas execuções
        // simultâneas com mesmo dayKey quebram o SwiftData store no save.
        // O upsert abaixo verifica `checkIns.first(where:)`, mas as duas
        // execuções podem ler dayKey ausente, ambas inserir e estourar a
        // unique constraint no `try modelContext.save()`.
        guard !isSavingCheckIn else { return }
        isSavingCheckIn = true
        defer { isSavingCheckIn = false }

        saveStatusMessage = ""

        let todayKey = DailyCheckIn.dayKey(for: Date())
        let checkIn: DailyCheckIn
        if let existing = checkIns.first(where: { $0.dayKey == todayKey }) {
            // Upsert: overwrite today's record rather than creating a duplicate.
            checkIn = existing
        } else {
            checkIn = DailyCheckIn(
                mood: mood, anxiety: anxiety, energy: energy,
                irritability: irritability, sleepHours: sleepHours,
                appetite: appetite, libido: libido,
                medicationTaken: isMedicationFullyTaken,
                sideEffects: sideEffects, automaticThoughts: automaticThoughts,
                suicidalIdeation: hasCriticalSafetyRisk,
                journalEntry: journalEntryWithContext
            )
            modelContext.insert(checkIn)
        }
        checkIn.date = Date()
        checkIn.mood = mood
        checkIn.anxiety = anxiety
        checkIn.energy = energy
        checkIn.irritability = irritability
        checkIn.sleepHours = sleepHours
        checkIn.appetite = appetite
        checkIn.libido = libido
        checkIn.medicationTaken = isMedicationFullyTaken
        checkIn.sideEffects = sideEffects
        checkIn.automaticThoughts = automaticThoughts
        checkIn.suicidalIdeation = hasCriticalSafetyRisk
        checkIn.journalEntry = journalEntryWithContext
        let backendPayload = BackendDailyCheckInPayload(
            mood: mood,
            anxiety: anxiety,
            energy: energy,
            irritability: irritability,
            sleepHours: sleepHours,
            appetite: appetite,
            libido: libido,
            medicationTaken: isMedicationFullyTaken,
            sideEffects: sideEffects,
            automaticThoughts: automaticThoughts,
            suicidalIdeation: hasCriticalSafetyRisk,
            journalEntry: journalEntryWithContext
        )

        let textAssessment = hasCriticalSafetyRisk
            ? TextRiskAssessment(level: .high, detectedTerms: ["triagem positiva"], explanation: "A triagem estruturada marcou ideação suicida.")
            : ClinicalAnalysis.textAssessment(for: "\(journalEntryWithContext) \(automaticThoughts)")
        if textAssessment.level != .low || mood <= 2 || anxiety >= 3.5 || !isMedicationFullyTaken {
            let alertLevel: ClinicalRiskLevel = textAssessment.level == .low ? .moderate : textAssessment.level
            modelContext.insert(ClinicalAlert(level: alertLevel, title: alertLevel.alertTitle, message: "\(textAssessment.explanation) \(textAssessment.recommendation)"))
        }

        // Sprint A — fluxo de crise (NEW-1): capturar AGORA os flags que
        // dependem do estado pré-reset. Antes:
        //   1. `journalEntry = ""` rodava em (linha do reset), aí logo abaixo
        //      `if journalEntry.trim.isEmpty` era SEMPRE true → postSaveSheet
        //      disparava sempre, inclusive em crise.
        //   2. `safetyStatus = .safe` resetava antes do paciente ver feedback
        //      de que a equipe foi acionada — `CrisisSupportCard` sumia.
        let wasUrgent = (safetyStatus == .urgent) || hasCriticalSafetyRisk
        let hadEmptyJournal = journalEntry
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        do {
            try modelContext.save()
            sideEffects = ""
            automaticThoughts = ""
            journalEntry = ""
            alcoholTrigger = false
            poorSleepTrigger = false
            stressTrigger = false
            conflictTrigger = false
            routineChangeTrigger = false
            menstrualTrigger = false
            customTriggers = []
            // Em crise: NÃO resetar safetyStatus (mantém CrisisSupportCard
            // visível) e dar feedback explícito de que a equipe foi alertada.
            if wasUrgent {
                saveStatusMessage = "Registro salvo e equipe de cuidado alertada. Continue acompanhando o plano de segurança abaixo."
            } else {
                safetyStatus = .safe
                saveStatusMessage = "Registro diário salvo no histórico."
            }
            hasSeenMoodCoachmark = true
            // Sprint 23 + Sprint A: só dispara o sheet de "anotação leve" se
            // o paciente NÃO estava em crise (essa UI seria deslocada) e se o
            // journal estava vazio ANTES do reset desta sessão de save.
            if !wasUrgent && hadEmptyJournal {
                postSaveThought = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isShowingPostSavePrompt = true
                }
            }
            syncCheckInWithBackend(backendPayload)
            if autoBackupEnabled {
                makeBackupExport(silent: true)
            }
            if autoMonthlyReportEnabled {
                prepareReportPreviewOnly()
                reportStatusMessage = "Relatório mensal atualizado."
                if autoCareTeamSendEnabled {
                    sendCurrentReportToCareTeam()
                }
            }
        } catch {
            saveStatusMessage = "Não foi possível salvar o registro."
        }
    }

    private func saveAutomaticCheckups() {
        scaleStatusMessage = ""
        let results = automaticCheckupResults

        for result in results {
            modelContext.insert(ScaleAssessment(
                scaleName: result.scale.rawValue,
                answers: result.answers,
                score: result.score,
                interpretation: result.interpretation
            ))

            if result.scale == .phq9 && result.answers.indices.contains(8) && result.answers[8] > 0 {
                modelContext.insert(ClinicalAlert(level: .high, title: "Check-up automático com item crítico", message: "Sinal de segurança alto. Revisar plano de apoio e contato profissional."))
            } else if scoreRequiresAlert(scale: result.scale, score: result.score) {
                modelContext.insert(ClinicalAlert(level: .moderate, title: "Check-up automático alterado", message: "\(result.scale.rawValue): \(result.score) pontos, interpretação \(result.interpretation)."))
            }
        }

        do {
            try modelContext.save()
            scaleStatusMessage = "Check-up automático salvo com base no diário de hoje."
            for result in results {
                syncAssessmentWithBackend(
                    scaleName: result.scale.rawValue,
                    answers: result.answers,
                    score: result.score,
                    interpretation: result.interpretation
                )
            }
        } catch {
            scaleStatusMessage = "Não foi possível salvar o check-up automático."
        }
    }

    private func automaticAnswers(for scale: ScaleKind) -> [Int] {
        switch scale {
        case .phq9:
            return [
                lowMoodSeverity,
                max(lowMoodSeverity, textSeverity),
                sleepSeverity,
                lowEnergySeverity,
                appetiteSeverity,
                textSeverity,
                automaticThoughts.isEmpty ? 0 : max(1, anxietySeverity - 1),
                max(lowEnergySeverity, irritabilitySeverity),
                safetySeverity
            ]
        case .gad7:
            return [
                anxietySeverity,
                automaticThoughts.isEmpty ? max(0, anxietySeverity - 1) : max(1, anxietySeverity),
                max(anxietySeverity, stressTrigger ? 2 : 0),
                max(anxietySeverity - 1, sleepSeverity),
                max(irritabilitySeverity, energy >= 4 ? 1 : 0),
                irritabilitySeverity,
                max(textSeverity, safetyStatus == .attention ? 1 : 0)
            ].map { clamped($0, range: 0...3) }
        case .ymrs:
            return [
                mood >= 4 ? Int(mood - 3) : 0,
                energy >= 4 ? Int(energy - 2) : 0,
                libido >= 4 ? Int(libido - 3) : 0,
                sleepHours < 5 ? 4 : sleepHours < 6 ? 3 : sleepHours < 7 ? 1 : 0,
                clamped(irritabilitySeverity * 2, range: 0...8),
                energy >= 5 ? 4 : energy >= 4 ? 2 : 0,
                automaticThoughts.count > 120 ? 3 : automaticThoughts.isEmpty ? 0 : 1,
                clamped(max(textSeverity, safetySeverity) * 2, range: 0...8),
                clamped(irritabilitySeverity * 2, range: 0...8),
                0,
                safetyStatus == .urgent ? 2 : safetyStatus == .attention ? 1 : 0
            ]
        }
    }

    private var lowMoodSeverity: Int {
        clamped(Int(((5 - mood) / 4 * 3).rounded()), range: 0...3)
    }

    private var anxietySeverity: Int {
        clamped(Int(((anxiety - 1) / 4 * 3).rounded()), range: 0...3)
    }

    private var lowEnergySeverity: Int {
        clamped(Int(((5 - energy) / 4 * 3).rounded()), range: 0...3)
    }

    private var irritabilitySeverity: Int {
        clamped(Int(((irritability - 1) / 4 * 3).rounded()), range: 0...3)
    }

    private var sleepSeverity: Int {
        if sleepHours < 5 { return 3 }
        if sleepHours < 6 { return 2 }
        if sleepHours < 7 || sleepHours > 9 { return 1 }
        return 0
    }

    private var appetiteSeverity: Int {
        let distance = abs(appetite - 3)
        if distance >= 2 { return 3 }
        if distance >= 1 { return 1 }
        return 0
    }

    private var safetySeverity: Int {
        switch safetyStatus {
        case .safe:
            0
        case .attention:
            1
        case .urgent:
            3
        }
    }

    private var textSeverity: Int {
        switch currentTextAssessment.level {
        case .low:
            0
        case .moderate:
            2
        case .high:
            3
        }
    }

    private func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func saveScaleAssessment() {
        scaleStatusMessage = ""
        ensureAnswers(for: selectedScale)
        let answers = scaleAnswers[selectedScale] ?? []
        let score = ClinicalAnalysis.score(for: selectedScale, answers: answers)
        let interpretation = ClinicalAnalysis.interpretation(for: selectedScale, score: score)
        modelContext.insert(ScaleAssessment(scaleName: selectedScale.rawValue, answers: answers, score: score, interpretation: interpretation))

        if selectedScale == .phq9 && answers.indices.contains(8) && answers[8] > 0 {
            modelContext.insert(ClinicalAlert(level: .high, title: "PHQ-9 com item crítico", message: "Item 9 positivo. Revisar risco suicida e plano de segurança imediatamente."))
        } else if scoreRequiresAlert(scale: selectedScale, score: score) {
            modelContext.insert(ClinicalAlert(level: .moderate, title: "Escala alterada", message: "\(selectedScale.rawValue): \(score) pontos, interpretação \(interpretation)."))
        }

        do {
            try modelContext.save()
            scaleAnswers[selectedScale] = Array(repeating: 0, count: selectedScale.questions.count)
            scaleStatusMessage = "\(selectedScale.rawValue) salvo: \(score) pontos, \(interpretation)."
            syncAssessmentWithBackend(scaleName: selectedScale.rawValue, answers: answers, score: score, interpretation: interpretation)
        } catch {
            scaleStatusMessage = "Não foi possível salvar \(selectedScale.rawValue)."
        }
    }

    private func scoreRequiresAlert(scale: ScaleKind, score: Int) -> Bool {
        switch scale {
        case .phq9:
            score >= 10
        case .gad7:
            score >= 10
        case .ymrs:
            score >= 13
        }
    }

    private func updateTypingSignals(text: String) {
        bodySignalInteractionCount += 1
        if typingStartedAt == nil && !text.isEmpty {
            typingStartedAt = Date()
            bodySignalTypingLatency = Date().timeIntervalSince(appSessionStartedAt)
        }

        guard let typingStartedAt else { return }
        let elapsedMinutes = max(Date().timeIntervalSince(typingStartedAt) / 60, 0.05)
        bodySignalTypingSpeed = Double(text.count) / elapsedMinutes
    }

    private func generateReport() {
        let text = ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments)
        reportPreview = text
        reportPDFURL = makePDFReport(text: text)
        reportCSVURL = makeCSVReport()
        let coveredCheckIns = sortedCheckIns.prefix(14)
        modelContext.insert(ClinicalReport(
            summary: text,
            riskLevel: summary.riskLevel,
            clinicianName: patients.first?.clinicianName ?? "",
            periodStart: coveredCheckIns.last?.date ?? Date(),
            periodEnd: coveredCheckIns.first?.date ?? Date(),
            scalesIncluded: Array(Set(sortedAssessments.prefix(10).map(\.scaleName))).sorted(),
            algorithmVersion: "2.0"
        ))
        reportStatusMessage = ""

        do {
            try modelContext.save()
            syncReportWithBackend(summary: text, riskLevel: summary.riskLevel.rawValue)
            if autoCareTeamSendEnabled {
                sendCurrentReportToCareTeam()
            }
        } catch {
            reportStatusMessage = "Relatório gerado, mas não foi possível salvar localmente."
        }
    }

    private func prepareReportPreviewOnly() {
        let text = ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments)
        reportPreview = text
        reportPDFURL = makePDFReport(text: text)
        reportCSVURL = makeCSVReport()
    }

    /// Encrypt a PHI string field for the backup JSON.
    /// Returns the base-64 AES-GCM ciphertext, or an empty string on failure
    /// (never falls back to plaintext — dropping is safer).
    private func encryptField(_ value: String) -> String {
        DraftStore.encryptString(value) ?? ""
    }

    private func makeBackupExport(silent: Bool = false) {
        // N-I5: single canonical format via NeuroFlowBackupSnapshot (Codable).
        // N-C1: PHI text fields are AES-GCM encrypted before serialisation.
        //       Email is omitted — not required to restore clinical records.
        let snapshot = NeuroFlowBackupSnapshot(
            profile: .init(role: activeRole.rawValue, careFocus: selectedCareFocus.rawValue),
            medicationPlan: .init(
                name: medicationName, dose: medicationDose, schedule: medicationSchedule,
                prescriptionEnc: encryptField(medicationPrescription),
                changeNoteEnc: encryptField(medicationChangeNote)
            ),
            medicationPlans: medicationPlans,
            customSymptoms: customSymptoms,
            safetyPlan: .init(
                contactEnc: encryptField(safetyContact),
                warningSignsEnc: encryptField(safetyWarningSigns),
                strategiesEnc: encryptField(safetyStrategies)
            ),
            offlineQueue: offlineSyncQueue,
            checkIns: sortedCheckIns.map { c in
                DailyCheckInSnapshot(
                    date: c.date, dayKey: c.dayKey,
                    mood: c.mood, anxiety: c.anxiety, energy: c.energy,
                    irritability: c.irritability, sleepHours: c.sleepHours,
                    appetite: c.appetite, libido: c.libido,
                    medicationTaken: c.medicationTaken, suicidalIdeation: c.suicidalIdeation,
                    sideEffectsEnc: encryptField(c.sideEffects),
                    automaticThoughtsEnc: encryptField(c.automaticThoughts),
                    journalEntryEnc: encryptField(c.journalEntry)
                )
            },
            assessments: sortedAssessments.map { a in
                ScaleAssessmentSnapshot(date: a.date, scaleName: a.scaleName,
                                        answers: a.answers, score: a.score,
                                        interpretation: a.interpretation)
            }
        )

        do {
            let data = try snapshot.encodedData()
            var url = BackupStore.protectedFileURL
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
            backupURL = url
            lastAutomaticBackupAt = Date().timeIntervalSince1970
            if !silent { loginStatusMessage = "Backup gerado." }
        } catch {
            if !silent { loginStatusMessage = "Não foi possível gerar backup." }
        }
    }

    private func runRecurringBackupIfNeeded() {
        guard autoBackupEnabled else { return }
        guard !checkIns.isEmpty || !assessments.isEmpty || !medicationPlans.isEmpty || !customSymptoms.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        let interval = TimeInterval(max(1, backupIntervalDays) * 86_400)
        if lastAutomaticBackupAt == 0 || now - lastAutomaticBackupAt >= interval {
            makeBackupExport(silent: true)
        }
    }

    private func sendCurrentReportToCareTeam() {
        guard autoCareTeamSendEnabled else { return }
        guard patients.first?.consentAccepted == true,
              (patients.first?.shareWithClinician == true || shareWithCaregiver) else {
            careTeamSendStatus = "Ative consentimento e autorização para médico ou cuidador."
            return
        }

        let text = reportPreview.isEmpty ? ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments) : reportPreview
        guard !text.isEmpty else {
            careTeamSendStatus = "Sem relatório para enviar."
            return
        }

        syncReportWithBackend(summary: text, riskLevel: summary.riskLevel.rawValue, automaticCareTeamSend: true)
    }

    @MainActor
    private func saveCaregiverContact() async {
        guard !authToken.isEmpty else {
            careTeamSendStatus = "Entre na conta para cadastrar cuidador no backend."
            return
        }
        guard shareWithCaregiver else {
            careTeamSendStatus = "Ative autorização para cuidador antes de cadastrar."
            return
        }
        let trimmedContact = careTeamContact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContact.isEmpty else {
            careTeamSendStatus = "Informe e-mail ou contato do cuidador."
            return
        }

        do {
            let payload = BackendCaregiverPayload(
                name: caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cuidador" : caregiverName,
                contact: trimmedContact,
                relationship: caregiverRelationship.trimmingCharacters(in: .whitespacesAndNewlines),
                shareEnabled: shareWithCaregiver
            )
            _ = try await BackendAuthClient.createCaregiver(payload, token: authToken)
            careTeamSendStatus = "Cuidador cadastrado e autorizado."
            await loadCaregivers()
        } catch {
            careTeamSendStatus = "Falha ao cadastrar cuidador: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadCaregivers() async {
        guard !authToken.isEmpty else { return }
        do {
            remoteCaregivers = try await BackendAuthClient.caregivers(token: authToken)
        } catch {
            careTeamSendStatus = "Falha ao carregar cuidadores: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func toggleCaregiverSharing(_ caregiver: BackendCaregiverContact) async {
        guard !authToken.isEmpty else { return }
        let payload = BackendCaregiverPayload(
            name: caregiver.name,
            contact: caregiver.contact,
            relationship: caregiver.relationship,
            shareEnabled: !caregiver.shareEnabled
        )
        do {
            _ = try await BackendAuthClient.updateCaregiver(id: caregiver.id, payload: payload, token: authToken)
            caregiverStatusMessage = caregiver.shareEnabled
                ? "Notificações pausadas para \(caregiver.name)."
                : "Notificações reativadas para \(caregiver.name)."
            await loadCaregivers()
        } catch {
            caregiverStatusMessage = "Falha ao atualizar \(caregiver.name): \(error.localizedDescription)"
        }
    }

    private func beginEditingCaregiver(_ caregiver: BackendCaregiverContact) {
        caregiverEditName = caregiver.name
        caregiverEditContact = caregiver.contact
        caregiverEditRelationship = caregiver.relationship
        caregiverEditShareEnabled = caregiver.shareEnabled
        caregiverEditTarget = caregiver
    }

    private func caregiverEditSheet(for caregiver: BackendCaregiverContact) -> some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome", text: $caregiverEditName)
                        .textContentType(.name)
                }
                Section("Contato (e-mail ou telefone)") {
                    // P1-8 (UX): keyboardType era .emailAddress, que não exibe
                    // teclado numérico por padrão — bloqueava entrada de telefone.
                    // .URL mostra @, ponto e números sem ocultar letras.
                    TextField("Contato", text: $caregiverEditContact)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section("Relação") {
                    TextField("Ex.: cônjuge, mãe, amigo", text: $caregiverEditRelationship)
                }
                Section {
                    Toggle("Receber alertas e relatórios", isOn: $caregiverEditShareEnabled)
                        .toggleStyle(.switch)
                }
            }
            .navigationTitle("Editar cuidador")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { caregiverEditTarget = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveCaregiverEdit(caregiver) }
                    } label: {
                        if isSavingCaregiverEdit {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Salvar")
                        }
                    }
                    .disabled(
                        isSavingCaregiverEdit
                        || caregiverEditName.trimmingCharacters(in: .whitespaces).isEmpty
                        || caregiverEditContact.trimmingCharacters(in: .whitespaces).count < 3
                    )
                }
            }
        }
    }

    @MainActor
    private func saveCaregiverEdit(_ caregiver: BackendCaregiverContact) async {
        guard !authToken.isEmpty else { return }
        isSavingCaregiverEdit = true
        defer { isSavingCaregiverEdit = false }
        let payload = BackendCaregiverPayload(
            name: caregiverEditName.trimmingCharacters(in: .whitespaces),
            contact: caregiverEditContact.trimmingCharacters(in: .whitespaces),
            relationship: caregiverEditRelationship.trimmingCharacters(in: .whitespaces),
            shareEnabled: caregiverEditShareEnabled
        )
        do {
            _ = try await BackendAuthClient.updateCaregiver(id: caregiver.id, payload: payload, token: authToken)
            caregiverStatusMessage = "\(payload.name) atualizado."
            caregiverEditTarget = nil
            await loadCaregivers()
        } catch {
            caregiverStatusMessage = "Falha ao atualizar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteCaregiver(_ caregiver: BackendCaregiverContact) async {
        guard !authToken.isEmpty else { return }
        do {
            try await BackendAuthClient.deleteCaregiver(id: caregiver.id, token: authToken)
            caregiverStatusMessage = "\(caregiver.name) removido."
            await loadCaregivers()
        } catch {
            caregiverStatusMessage = "Falha ao remover \(caregiver.name): \(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportMyAccount() async {
        guard !authToken.isEmpty else {
            privacyStatusMessage = "Entre na conta para exportar seus dados."
            return
        }
        privacyStatusMessage = "Solicitando exportação..."
        do {
            let data = try await BackendAuthClient.exportAccount(token: authToken)
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = documents.appending(path: "neuroflow-export-\(timestamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            privacyExportURL = url
            privacyStatusMessage = "Exportação pronta. Use o botão de compartilhamento abaixo."
        } catch {
            privacyStatusMessage = "Falha ao exportar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteOldClinicalData() async {
        guard !authToken.isEmpty else { return }
        privacyStatusMessage = "Apagando dados antigos..."
        do {
            let response = try await BackendAuthClient.deleteOldClinicalData(daysOlderThan: privacyRetentionDays, token: authToken)
            privacyStatusMessage = "Removidos do backend: \(response.deletedCheckins) check-ins, \(response.deletedAssessments) escalas, \(response.deletedAlerts) alertas, \(response.deletedReports) relatórios."
        } catch {
            privacyStatusMessage = "Falha ao apagar dados antigos: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteMyAccount() async {
        guard !authToken.isEmpty else { return }
        privacyStatusMessage = "Apagando conta..."
        do {
            let response = try await BackendAuthClient.deleteAccount(token: authToken)
            privacyStatusMessage = response.message
            logout()
        } catch {
            privacyStatusMessage = "Falha ao apagar conta: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func fetchAuditLogs() async {
        guard !authToken.isEmpty else { return }
        do {
            remoteAuditLogs = try await BackendAuthClient.auditLogs(token: authToken)
            isShowingAuditLogs = true
        } catch {
            privacyStatusMessage = "Falha ao carregar auditoria: \(error.localizedDescription)"
        }
    }

    /// Backend creates ClinicalAlert rows when a high-risk check-in is submitted.
    /// Pull them into local SwiftData so the patient actually sees them in the
    /// "Alertas acionáveis" section instead of only the clinician dashboard.
    @MainActor
    private func syncMyBackendAlerts() async {
        guard !authToken.isEmpty,
              authenticatedUserId > 0,
              activeRole == .patient else {
            return
        }

        do {
            let backendAlerts = try await BackendAuthClient.patientAlerts(
                patientId: authenticatedUserId,
                token: authToken
            )
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]

            var insertedAny = false
            for backendAlert in backendAlerts {
                let date = isoWithFraction.date(from: backendAlert.createdAt)
                    ?? isoBasic.date(from: backendAlert.createdAt)
                    ?? Date()

                let alreadyExists = alerts.contains { existing in
                    existing.title == backendAlert.title
                        && existing.message == backendAlert.message
                        && abs(existing.date.timeIntervalSince(date)) < 5
                }
                guard !alreadyExists else { continue }

                modelContext.insert(ClinicalAlert(
                    date: date,
                    level: Self.backendLevelToClinical(backendAlert.level),
                    title: backendAlert.title,
                    message: backendAlert.message,
                    acknowledged: backendAlert.acknowledged
                ))
                insertedAny = true
            }

            if insertedAny {
                try? modelContext.save()
            }
        } catch {
            // Silent: patient still sees locally generated alerts.
        }
    }

    /// Pull `screen.isCaptured` via the new windowScene API (UIScreen.main
    /// was deprecated in iOS 26).
    static var activeScreenIsCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.isCaptured ?? false
    }

    static func backendLevelToClinical(_ level: String) -> ClinicalRiskLevel {
        switch level.lowercased() {
        case "high", "critical", "urgent":
            return .high
        case "moderate", "medium":
            return .moderate
        case "low", "minimal", "normal":
            return .low
        default:
            // Unknown severity from the backend (e.g. a future tier not yet
            // reflected here) MUST NOT be silently downgraded to .low. Treat
            // it as moderate so the patient/clinician is at least nudged to
            // review it manually. Log so the team knows to add a case.
            assertionFailure("backendLevelToClinical: unrecognised level '\(level)' — add a case")
            return .moderate
        }
    }

    @MainActor
    private func requestRemotePushRegistration() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                remotePushStatus = "Permissão de push negada."
                return
            }

            remotePushEnabled = true
            remotePushStatus = "Registrando no APNs..."
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            remotePushStatus = "Falha ao solicitar push: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func uploadPushTokenToBackend() async {
        let token = apnsDeviceToken.isEmpty
            ? KeychainStore.string(for: .apnsDeviceToken) ?? ""
            : apnsDeviceToken
        guard !token.isEmpty else {
            remotePushStatus = "Token APNs ainda não disponível."
            return
        }
        guard !authToken.isEmpty else {
            remotePushStatus = "Entre na conta para vincular o token ao backend."
            return
        }

        do {
            try await BackendAuthClient.registerPushToken(token: token, platform: "ios", token: authToken)
            apnsDeviceToken = token
            remotePushStatus = "Token APNs enviado ao backend."
        } catch {
            remotePushStatus = "Falha ao enviar token: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestHealthKitAccessAndSync() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitStatus = "HealthKit não disponível neste dispositivo."
            return
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            healthKitStatus = "Tipos do Apple Health indisponíveis."
            return
        }

        let readTypes: Set<HKObjectType> = [stepType, heartRateType, activeEnergyType, sleepType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            async let steps = quantitySum(for: stepType, unit: .count())
            async let energy = quantitySum(for: activeEnergyType, unit: .kilocalorie())
            async let heartRate = quantityAverage(for: heartRateType, unit: HKUnit.count().unitDivided(by: .minute()))
            async let sleep = sleepHoursFromHealthKit(sleepType: sleepType)

            healthSteps = Int(try await steps)
            healthActiveEnergy = try await energy
            healthHeartRate = try await heartRate
            healthSleepHours = try await sleep
            if healthSleepHours > 0 {
                sleepHours = healthSleepHours
            }
            healthKitEnabled = true
            healthKitStatus = "Apple Health sincronizado."
        } catch {
            healthKitStatus = "Falha ao acessar Apple Health: \(error.localizedDescription)"
        }
        #else
        healthKitStatus = "HealthKit não está disponível neste alvo."
        #endif
    }

    #if canImport(HealthKit)
    private func dayPredicate() -> NSPredicate {
        let start = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    }

    private func quantitySum(for type: HKQuantityType, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: dayPredicate(), options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private func quantityAverage(for type: HKQuantityType, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: dayPredicate(), options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private func sleepHoursFromHealthKit(sleepType: HKCategoryType) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sleepSeconds = (samples as? [HKCategorySample] ?? []).reduce(0.0) { total, sample in
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    switch value {
                    case .asleep, .asleepCore, .asleepDeep, .asleepREM:
                        return total + sample.endDate.timeIntervalSince(sample.startDate)
                    default:
                        return total
                    }
                }
                continuation.resume(returning: sleepSeconds / 3600)
            }
            healthStore.execute(query)
        }
    }
    #endif

    private func handleBackupImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            try restoreBackup(from: data)
            loginStatusMessage = "Backup restaurado."
        } catch {
            loginStatusMessage = "Não foi possível restaurar o backup."
        }
    }

    private func restoreBackup(from data: Data) throws {
        // N-I5: parse via the canonical NeuroFlowBackupSnapshot type.
        // Falls back to legacy [String:Any] parsing for files produced
        // before schema v2 (missing schemaVersion key).
        if let snapshot = try? NeuroFlowBackupSnapshot.decode(from: data) {
            try restoreFromSnapshot(snapshot)
        } else {
            try restoreFromLegacyPayload(data)
        }

        var importedURL = BackupStore.protectedFileURL
        if (try? data.write(to: importedURL, options: [.atomic, .completeFileProtection])) != nil {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? importedURL.setResourceValues(resourceValues)
            backupURL = importedURL
        }
    }

    private func restoreFromSnapshot(_ snapshot: NeuroFlowBackupSnapshot) throws {
        let existingDayKeys = Set(checkIns.map(\.dayKey))
        for c in snapshot.checkIns {
            guard !existingDayKeys.contains(c.dayKey) else { continue }
            modelContext.insert(DailyCheckIn(
                date: c.date,
                mood: c.mood.clamped(to: 0...5), anxiety: c.anxiety.clamped(to: 0...5),
                energy: c.energy.clamped(to: 0...5), irritability: c.irritability.clamped(to: 0...5),
                sleepHours: c.sleepHours.clamped(to: 0...24),
                appetite: c.appetite.clamped(to: 0...5), libido: c.libido.clamped(to: 0...5),
                medicationTaken: c.medicationTaken,
                sideEffects: decryptField(c.sideEffectsEnc),
                automaticThoughts: decryptField(c.automaticThoughtsEnc),
                suicidalIdeation: c.suicidalIdeation,
                journalEntry: decryptField(c.journalEntryEnc)
            ))
        }
        let existingAssessments = assessments
        for a in snapshot.assessments {
            let alreadyExists = existingAssessments.contains {
                $0.scaleName == a.scaleName && abs($0.date.timeIntervalSince(a.date)) < 1
            }
            guard !alreadyExists else { continue }
            modelContext.insert(ScaleAssessment(
                scaleName: a.scaleName, date: a.date,
                answers: a.answers.map { min(max($0, 0), 8) },
                score: max(a.score, 0), interpretation: String(a.interpretation.prefix(500))
            ))
        }
        medicationPlans = snapshot.medicationPlans
        persistMedicationPlans()
        customSymptoms = snapshot.customSymptoms
        persistCustomSymptoms()
        safetyContact = decryptField(snapshot.safetyPlan.contactEnc, fallback: safetyContact)
        safetyWarningSigns = decryptField(snapshot.safetyPlan.warningSignsEnc, fallback: safetyWarningSigns)
        safetyStrategies = decryptField(snapshot.safetyPlan.strategiesEnc, fallback: safetyStrategies)
        try modelContext.save()
    }

    /// Legacy path for backups produced before schema v2.
    private func restoreFromLegacyPayload(_ data: Data) throws {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let formatter = ISO8601DateFormatter()
        if let checkInPayloads = payload["checkIns"] as? [[String: Any]] {
            let existingCheckIns = checkIns
            for item in checkInPayloads {
                let date = (item["date"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
                let importedDayKey = DailyCheckIn.dayKey(for: date)
                guard !existingCheckIns.contains(where: { $0.dayKey == importedDayKey }) else { continue }
                modelContext.insert(DailyCheckIn(
                    date: date,
                    mood: clampedScalar(item["mood"], range: 0...5, fallback: 3),
                    anxiety: clampedScalar(item["anxiety"], range: 0...5, fallback: 2),
                    energy: clampedScalar(item["energy"], range: 0...5, fallback: 3),
                    irritability: clampedScalar(item["irritability"], range: 0...5, fallback: 1),
                    sleepHours: clampedScalar(item["sleepHours"], range: 0...24, fallback: 7),
                    appetite: clampedScalar(item["appetite"], range: 0...5, fallback: 3),
                    libido: clampedScalar(item["libido"], range: 0...5, fallback: 3),
                    medicationTaken: item["medicationTaken"] as? Bool ?? false,
                    sideEffects: decryptField(item["sideEffects"]),
                    automaticThoughts: decryptField(item["automaticThoughts"]),
                    suicidalIdeation: item["suicidalIdeation"] as? Bool ?? false,
                    journalEntry: decryptField(item["journalEntry"])
                ))
            }
        }
        if let assessmentPayloads = payload["assessments"] as? [[String: Any]] {
            let existingAssessments = assessments
            for item in assessmentPayloads {
                let date = (item["date"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
                let scaleName = sanitizedString(item["scaleName"], fallback: "Escala")
                guard !existingAssessments.contains(where: {
                    $0.scaleName == scaleName && abs($0.date.timeIntervalSince(date)) < 1
                }) else { continue }
                let answers = (item["answers"] as? [Int] ?? []).map { min(max($0, 0), 8) }
                modelContext.insert(ScaleAssessment(
                    scaleName: scaleName, date: date, answers: answers,
                    score: max(item["score"] as? Int ?? 0, 0),
                    interpretation: sanitizedString(item["interpretation"])
                ))
            }
        }
        if let safetyPlan = payload["safetyPlan"] as? [String: Any] {
            safetyContact = decryptField(safetyPlan["contact"], fallback: safetyContact)
            safetyWarningSigns = decryptField(safetyPlan["warningSigns"], fallback: safetyWarningSigns)
            safetyStrategies = decryptField(safetyPlan["strategies"], fallback: safetyStrategies)
        }
        try modelContext.save()
    }

    /// Best-effort coercion of an Any? backup field into a Double clamped
    /// to the expected clinical range. Strings like "3.5" are accepted as
    /// a courtesy (older backups exported them as such).
    private func clampedScalar(_ raw: Any?, range: ClosedRange<Double>, fallback: Double) -> Double {
        let candidate: Double?
        switch raw {
        case let value as Double:
            candidate = value
        case let value as Int:
            candidate = Double(value)
        case let value as NSNumber:
            candidate = value.doubleValue
        case let value as String:
            candidate = Double(value)
        default:
            candidate = nil
        }
        guard let value = candidate, value.isFinite, range.contains(value) else {
            return fallback
        }
        return value
    }

    /// Strips surrounding whitespace and limits length so a maliciously
    /// crafted backup cannot inflate SwiftData rows arbitrarily.
    private func sanitizedString(_ raw: Any?, fallback: String = "") -> String {
        guard let value = raw as? String else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(8_000))
    }

    /// Decrypt a PHI field from the backup JSON (N-C1).
    /// Falls back to treating the value as plaintext for backward compatibility
    /// with backups created before encryption was introduced.
    private func decryptField(_ raw: Any?, fallback: String = "") -> String {
        guard let value = raw as? String, !value.isEmpty else { return fallback }
        // Try to decrypt — if it fails, the value may be a legacy plaintext field.
        if let decrypted = DraftStore.decryptString(value) {
            return String(decrypted.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
        }
        // Legacy plaintext fallback (backups before N-C1 fix).
        return sanitizedString(raw, fallback: fallback)
    }

    @MainActor
    private func configureLocalReminders() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                loginStatusMessage = "Permissão de notificação não concedida."
                return
            }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["neuroflow.medication", "neuroflow.checkin"])

            if medicationReminderEnabled {
                scheduleDailyNotification(
                    id: "neuroflow.medication",
                    title: "Hora da medicação",
                    body: "Registre se tomou sua medicação e como está se sentindo.",
                    hour: medicationReminderHour
                )
            }

            if checkInReminderEnabled {
                scheduleDailyNotification(
                    id: "neuroflow.checkin",
                    title: "Check-in NeuroFlow",
                    body: "Leva menos de um minuto para registrar seu dia.",
                    hour: checkInReminderHour
                )
            }

            loginStatusMessage = "Lembretes configurados."
        } catch {
            loginStatusMessage = "Não foi possível configurar lembretes: \(error.localizedDescription)"
        }
    }

    private func scheduleDailyNotification(id: String, title: String, body: String, hour: Int) {
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func makeCSVReport() -> URL? {
        var rows = ["type,date,mood,anxiety,energy,irritability,sleep_hours,medication_taken,suicidal_ideation,scale,score,interpretation"]
        for checkIn in sortedCheckIns {
            rows.append([
                "check_in",
                ISO8601DateFormatter().string(from: checkIn.date),
                String(format: "%.1f", checkIn.mood),
                String(format: "%.1f", checkIn.anxiety),
                String(format: "%.1f", checkIn.energy),
                String(format: "%.1f", checkIn.irritability),
                String(format: "%.1f", checkIn.sleepHours),
                checkIn.medicationTaken ? "true" : "false",
                checkIn.suicidalIdeation ? "true" : "false",
                "",
                "",
                ""
            ].joined(separator: ","))
        }

        for assessment in sortedAssessments {
            rows.append([
                "assessment",
                ISO8601DateFormatter().string(from: assessment.date),
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                assessment.scaleName,
                "\(assessment.score)",
                csvEscaped(assessment.interpretation)
            ].joined(separator: ","))
        }

        let url = FileManager.default.temporaryDirectory.appending(path: "neuroflow-registros.csv")
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func makePDFReport(text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "neuroflow-relatorio.pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let margin: CGFloat = 36
                var y = margin
                let width = pageRect.width - margin * 2

                drawPDFText("NeuroFlow", in: CGRect(x: margin, y: y, width: width, height: 34), font: .boldSystemFont(ofSize: 24), color: .black)
                y += 34
                drawPDFText("Relatório para consulta", in: CGRect(x: margin, y: y, width: width, height: 22), font: .systemFont(ofSize: 14), color: .darkGray)
                y += 30

                UIColor.neuroGold.setFill()
                context.cgContext.fill(CGRect(x: margin, y: y, width: width, height: 3))
                y += 18

                let summaryLines = [
                    "Gerado em: \(Date().formatted(date: .abbreviated, time: .shortened))",
                    "Risco atual: \(summary.riskLevel.rawValue)",
                    "Registros analisados: \(summary.analyzedCheckInCount)",
                    "Sono médio: \(String(format: "%.1f", summary.averageSleep))h",
                    "Adesão medicamentosa: \(String(format: "%.0f", summary.medicationAdherence * 100))%"
                ]

                y = drawPDFSection("Resumo", lines: summaryLines, x: margin, y: y, width: width)
                y = drawPDFTrendChart(x: margin, y: y + 8, width: width, context: context.cgContext)
                y = drawPDFSection("Sinais recentes", lines: summary.signals, x: margin, y: y + 10, width: width)

                let scaleLines = sortedAssessments.prefix(6).map { "\($0.scaleName): \($0.score) pontos - \($0.interpretation)" }
                y = drawPDFSection("Escalas", lines: scaleLines.isEmpty ? ["Nenhuma escala salva."] : scaleLines, x: margin, y: y + 10, width: width)

                y = drawPDFSection("Resumo mensal", lines: monthlyPDFLines(), x: margin, y: y + 10, width: width)

                let medicationLines = medicationPlans.map { plan in
                    [plan.name, plan.dose, plan.schedule, plan.prescription, plan.changeNote]
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                }
                y = drawPDFSection("Medicações", lines: medicationLines.isEmpty ? ["Nenhum medicamento cadastrado."] : medicationLines, x: margin, y: y + 10, width: width)

                let customSymptomLines = customSymptoms.map { "\($0.name): \(String(format: "%.0f", $0.value))/5" }
                y = drawPDFSection("Sintomas personalizados", lines: customSymptomLines.isEmpty ? ["Nenhum sintoma personalizado cadastrado."] : customSymptomLines, x: margin, y: y + 10, width: width)

                let checkInLines = sortedCheckIns.prefix(8).map {
                    "\($0.date.formatted(date: .numeric, time: .omitted)): humor \(String(format: "%.1f", $0.mood)), ansiedade \(String(format: "%.1f", $0.anxiety)), sono \(String(format: "%.1f", $0.sleepHours))h"
                }
                y = drawPDFSection("Registros recentes", lines: checkInLines.isEmpty ? ["Nenhum registro salvo."] : checkInLines, x: margin, y: y + 10, width: width)

                let disclaimer = "Análise automatizada de apoio. Este relatório não substitui julgamento médico, atendimento emergencial ou validação clínica formal."
                _ = drawPDFSection("Observação", lines: [disclaimer], x: margin, y: y + 10, width: width)
            }
            return url
        } catch {
            return nil
        }
    }

    private func monthlyPDFLines() -> [String] {
        MonthlyReportSummary.lines(for: sortedCheckIns)
    }

    private func drawPDFTrendChart(x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) -> CGFloat {
        drawPDFText("Evolução visual recente", in: CGRect(x: x, y: y, width: width, height: 22), font: .boldSystemFont(ofSize: 15), color: .black)
        let chartY = y + 28
        let chartHeight: CGFloat = 76
        let entries = Array(sortedCheckIns.prefix(7).reversed())
        guard !entries.isEmpty else {
            drawPDFText("Sem dados suficientes para gráfico.", in: CGRect(x: x, y: chartY, width: width, height: 24), font: .systemFont(ofSize: 11), color: .darkGray)
            return chartY + 34
        }

        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.stroke(CGRect(x: x, y: chartY, width: width, height: chartHeight))

        let barWidth = max(12, (width - CGFloat(entries.count - 1) * 8) / CGFloat(entries.count))
        for (index, entry) in entries.enumerated() {
            let barX = x + CGFloat(index) * (barWidth + 8)
            let moodHeight = CGFloat(entry.mood / 5) * chartHeight
            UIColor.neuroGold.setFill()
            context.fill(CGRect(x: barX, y: chartY + chartHeight - moodHeight, width: barWidth, height: moodHeight))
        }

        drawPDFText("Barras amarelas: humor recente de 1 a 5.", in: CGRect(x: x, y: chartY + chartHeight + 6, width: width, height: 18), font: .systemFont(ofSize: 10), color: .darkGray)
        return chartY + chartHeight + 28
    }

    private func drawPDFSection(_ title: String, lines: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var currentY = y
        drawPDFText(title, in: CGRect(x: x, y: currentY, width: width, height: 22), font: .boldSystemFont(ofSize: 15), color: .black)
        currentY += 24

        for line in lines {
            let rect = CGRect(x: x, y: currentY, width: width, height: 36)
            drawPDFText("• \(line)", in: rect, font: .systemFont(ofSize: 11), color: .darkGray)
            currentY += 28
        }

        return currentY
    }

    private func drawPDFText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    private func enqueueSyncItem<T: Codable>(kind: OfflineSyncKind, payload: T, summary: String) {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        offlineSyncQueue.append(OfflineSyncItem(kind: kind, payloadJSON: json, summary: summary))
        persistOfflineSyncQueue()
        lastSyncStatus = "\(offlineSyncQueue.count) item(ns) pendente(s)"
    }

    private func retryPendingSync() {
        guard !authToken.isEmpty else {
            lastSyncStatus = "Entre na conta para sincronizar pendências."
            return
        }
        guard !offlineSyncQueue.isEmpty else {
            lastSyncStatus = "Tudo sincronizado."
            return
        }

        let queuedItems = offlineSyncQueue
        Task {
            var remaining: [OfflineSyncItem] = []
            let decoder = JSONDecoder()

            for item in queuedItems {
                do {
                    guard let data = item.payloadJSON.data(using: .utf8) else {
                        continue
                    }

                    switch item.kind {
                    case .checkIn:
                        let payload = try decoder.decode(BackendDailyCheckInPayload.self, from: data)
                        try await BackendAuthClient.createCheckIn(payload, token: authToken)
                    case .assessment:
                        let payload = try decoder.decode(BackendScaleAssessmentPayload.self, from: data)
                        try await BackendAuthClient.createAssessment(payload, token: authToken)
                    case .report:
                        let payload = try decoder.decode(BackendClinicalReportPayload.self, from: data)
                        try await BackendAuthClient.createReport(payload, token: authToken)
                    }
                } catch {
                    remaining.append(item)
                }
            }

            await MainActor.run {
                offlineSyncQueue = remaining
                persistOfflineSyncQueue()
                lastSyncStatus = remaining.isEmpty ? "Tudo sincronizado." : "\(remaining.count) item(ns) ainda pendente(s)."
            }
        }
    }

    private func syncCheckInWithBackend(_ payload: BackendDailyCheckInPayload) {
        guard !authToken.isEmpty else {
            enqueueSyncItem(kind: .checkIn, payload: payload, summary: "Registro diário")
            saveStatusMessage = "Registro salvo localmente. Entre na conta para sincronizar."
            return
        }

        Task {
            do {
                try await BackendAuthClient.createCheckIn(payload, token: authToken)
                await MainActor.run {
                    lastSyncStatus = "Registro sincronizado."
                    saveStatusMessage = "Registro salvo e sincronizado."
                }
            } catch {
                await MainActor.run {
                    enqueueSyncItem(kind: .checkIn, payload: payload, summary: "Registro diário")
                    saveStatusMessage = "Registro salvo localmente. Falha ao sincronizar: \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncAssessmentWithBackend(scaleName: String, answers: [Int], score: Int, interpretation: String) {
        let payload = BackendScaleAssessmentPayload(scaleName: scaleName, answers: answers, score: score, interpretation: interpretation)
        guard !authToken.isEmpty else {
            enqueueSyncItem(kind: .assessment, payload: payload, summary: scaleName)
            scaleStatusMessage = "\(scaleName) salvo localmente. Entre na conta para sincronizar."
            return
        }

        Task {
            do {
                try await BackendAuthClient.createAssessment(payload, token: authToken)
                await MainActor.run {
                    lastSyncStatus = "\(scaleName) sincronizado."
                    scaleStatusMessage = "\(scaleName) salvo e sincronizado."
                }
            } catch {
                await MainActor.run {
                    enqueueSyncItem(kind: .assessment, payload: payload, summary: scaleName)
                    scaleStatusMessage = "\(scaleName) salvo localmente. Falha ao sincronizar: \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncReportWithBackend(summary: String, riskLevel: String, automaticCareTeamSend: Bool = false) {
        let payload = BackendClinicalReportPayload(
            riskLevel: riskLevel,
            summary: summary,
            autoSend: automaticCareTeamSend,
            careTeamContact: automaticCareTeamSend ? careTeamContact : nil,
            apnsToken: automaticCareTeamSend ? apnsDeviceToken : nil
        )
        guard !authToken.isEmpty else {
            enqueueSyncItem(kind: .report, payload: payload, summary: "Relatório")
            reportStatusMessage = "Relatório salvo localmente. Entre na conta para sincronizar."
            if automaticCareTeamSend {
                careTeamSendStatus = "Relatório ficou pendente até entrar na conta."
            }
            return
        }

        Task {
            do {
                try await BackendAuthClient.createReport(payload, token: authToken)
                await MainActor.run {
                    lastSyncStatus = "Relatório sincronizado."
                    reportStatusMessage = "Relatório sincronizado."
                    if automaticCareTeamSend {
                        let target = careTeamContact.isEmpty ? "médico/cuidador vinculado" : careTeamContact
                        careTeamSendStatus = "Relatório enviado para \(target)."
                    }
                }
            } catch {
                await MainActor.run {
                    enqueueSyncItem(kind: .report, payload: payload, summary: "Relatório")
                    reportStatusMessage = "Relatório salvo localmente. Falha ao sincronizar: \(error.localizedDescription)"
                    if automaticCareTeamSend {
                        careTeamSendStatus = "Envio pendente. O app tentará sincronizar depois."
                    }
                }
            }
        }
    }

    @MainActor
    private func handleAuthenticationButton() async {
        if isLoggedIn {
            logout()
        } else if isCreatingAccount {
            await register()
        } else {
            await login()
        }
    }

    @MainActor
    private func login() async {
        isAuthenticating = true
        loginStatusMessage = ""

        do {
            let response = try await BackendAuthClient.login(email: loginEmail, password: loginPassword)
            authToken = response.accessToken
            refreshToken = response.refreshToken
            authenticatedEmail = response.user.email
            authenticatedName = response.user.fullName
            authenticatedRole = response.user.role
            authenticatedUserId = response.user.id
            loginPassword = ""
            applyRole(from: response.user.role)
            await loadCaregivers()
            await syncMyBackendAlerts()
            await loadPendingInvites()
            await loadLinkedClinicians()
            await loadClinicianSentInvites()
            loginStatusMessage = "Login realizado com sucesso."
        } catch {
            loginStatusMessage = error.localizedDescription
        }

        isAuthenticating = false
    }

    @MainActor
    private func register() async {
        isAuthenticating = true
        loginStatusMessage = ""

        do {
            // Backend self-service signup always creates a patient account.
            // Clinician promotion is gated behind the admin endpoint.
            let response = try await BackendAuthClient.register(email: loginEmail, password: loginPassword, fullName: fullName)
            authToken = response.accessToken
            refreshToken = response.refreshToken
            authenticatedEmail = response.user.email
            authenticatedName = response.user.fullName
            authenticatedRole = response.user.role
            authenticatedUserId = response.user.id
            loginPassword = ""
            isCreatingAccount = false
            applyRole(from: response.user.role)
            await loadCaregivers()
            await syncMyBackendAlerts()
            await loadPendingInvites()
            await loadLinkedClinicians()
            await loadClinicianSentInvites()
            loginStatusMessage = "Conta criada e conectada."
        } catch {
            loginStatusMessage = error.localizedDescription
        }

        isAuthenticating = false
    }

    /// Sheet pós-save (Sprint 23): oferece, sem fricção, espaço pra
    /// acrescentar um pensamento ou contexto ao check-in que acabou de
    /// ser gravado.
    private var postSaveThoughtSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $postSaveThought)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Algo passou pela sua cabeça hoje?")
                } footer: {
                    Text("Opcional. Vai ser anexado ao registro que você acabou de salvar.")
                }
                Section {
                    Button {
                        appendThoughtToLatestCheckIn()
                        isShowingPostSavePrompt = false
                        postSaveThought = ""
                    } label: {
                        Label("Adicionar", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(postSaveThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Registro salvo ✓")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Pular") {
                        isShowingPostSavePrompt = false
                        postSaveThought = ""
                    }
                }
            }
        }
    }

    @MainActor
    private func appendThoughtToLatestCheckIn() {
        guard let latest = sortedCheckIns.first else { return }
        let trimmed = postSaveThought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prefix = latest.journalEntry.isEmpty ? "" : latest.journalEntry + "\n\n"
        latest.journalEntry = prefix + trimmed
        try? modelContext.save()
    }

    private var passwordResetConfirmSheet: some View {
        NavigationStack {
            Form {
                Section("E-mail") {
                    TextField("E-mail", text: $loginEmail)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                Section {
                    TextField("Cole aqui o código", text: $passwordResetCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Código recebido por e-mail")
                } footer: {
                    Text("O código expira em 30 minutos e pode ser usado uma única vez.")
                }

                Section {
                    SecureField("Nova senha (mínimo 8)", text: $passwordResetNewPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("Nova senha")
                }

                if !passwordResetStatusMessage.isEmpty {
                    Label(passwordResetStatusMessage, systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await confirmPasswordReset() }
                    } label: {
                        HStack {
                            if isConfirmingPasswordReset { ProgressView().controlSize(.small) }
                            Text(isConfirmingPasswordReset ? "Confirmando..." : "Definir nova senha")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isConfirmingPasswordReset
                        || loginEmail.isEmpty
                        || passwordResetCode.count < 8
                        || passwordResetNewPassword.count < 8
                    )
                }
            }
            .navigationTitle("Redefinir senha")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        isShowingPasswordResetConfirm = false
                        passwordResetCode = ""
                        passwordResetNewPassword = ""
                    }
                }
            }
        }
    }

    @MainActor
    private func confirmPasswordReset() async {
        isConfirmingPasswordReset = true
        defer { isConfirmingPasswordReset = false }
        do {
            let message = try await BackendAuthClient.confirmPasswordReset(
                email: loginEmail,
                resetCode: passwordResetCode,
                newPassword: passwordResetNewPassword
            )
            passwordResetCode = ""
            passwordResetNewPassword = ""
            isShowingPasswordResetConfirm = false
            loginStatusMessage = message
        } catch {
            passwordResetStatusMessage = "Falha: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestPasswordReset() async {
        isRequestingPasswordReset = true
        loginStatusMessage = ""

        do {
            loginStatusMessage = try await BackendAuthClient.requestPasswordReset(email: loginEmail)
        } catch {
            loginStatusMessage = "Não foi possível solicitar recuperação: \(error.localizedDescription)"
        }

        isRequestingPasswordReset = false
    }

    private func logout() {
        // Best-effort: revoke refresh token on the backend so a stolen access
        // token can be cut short. Failures don't block local cleanup — user
        // may be offline. The access token expires anyway within 2h.
        if !refreshToken.isEmpty && !authToken.isEmpty {
            let pendingRefresh = refreshToken
            let pendingAccess = authToken
            Task {
                try? await BackendAuthClient.logout(refreshToken: pendingRefresh, accessToken: pendingAccess)
            }
        }

        authToken = ""
        refreshToken = ""
        apnsDeviceToken = ""
        authenticatedEmail = ""
        authenticatedName = ""
        authenticatedRole = ""
        authenticatedUserId = 0
        loginStatusMessage = "Sessão encerrada."
        loginPassword = ""

        // Clear cached clinical data so the next user on the same device
        // never sees the previous account's information.
        medicationPlansData = ""
        customSymptomsData = ""
        offlineSyncQueueData = ""
        // S15/C1: delete the protected backup file so PHI from the previous
        // session is never accessible to whoever logs in next on this device.
        try? FileManager.default.removeItem(at: BackupStore.protectedFileURL)
        backupURL = nil
        medicationPlans = []
        customSymptoms = []
        offlineSyncQueue = []
        remoteCaregivers = []
        clinicianPatients = []
        selectedRemotePatient = nil
        remoteCheckIns = []
        remoteAssessments = []
        remoteAlerts = []
        remoteReports = []
        pendingClinicianInvites = []
        // Sprint A: drafts encriptados (mood/anxiety/journal/safetyContact etc.)
        // ainda ficavam no DraftStore após logout — PHI do usuário A visível
        // ao usuário B no mesmo device. Limpa tudo no logout e no listener
        // de sessionExpired.
        clearAllLocalPHIDrafts()
    }

    /// Sprint A: limpa todos os @EncryptedDraft + safetyStatus. Chamado em
    /// `logout()` e no listener `.neuroFlowSessionExpired` para garantir que
    /// PHI do usuário anterior não vaza para o próximo login no mesmo device.
    /// Setar a property re-escreve ciphertext com o defaultValue (não vaza
    /// PHI) e também limpa o @State cached em memória do EncryptedDraft.
    private func clearAllLocalPHIDrafts() {
        mood = 3.0
        anxiety = 2.0
        energy = 3.0
        irritability = 1.0
        sleepHours = 7.0
        appetite = 3.0
        libido = 0.0  // 0 = "Não se aplica" (P2-7)
        sideEffects = ""
        automaticThoughts = ""
        journalEntry = ""
        safetyContact = ""
        safetyWarningSigns = ""
        safetyStrategies = ""
        safetyStatus = .safe
    }

    @MainActor
    private func loadClinicianSentInvites() async {
        guard !authToken.isEmpty, activeRole == .clinician else { return }
        isLoadingClinicianSentInvites = true
        defer { isLoadingClinicianSentInvites = false }
        do {
            clinicianSentInvites = try await BackendAuthClient.clinicianSentInvites(token: authToken)
            withAnimation { clinicianSentInvitesFlash = "Lista atualizada." }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { clinicianSentInvitesFlash = "" }
            }
        } catch {
            withAnimation { clinicianSentInvitesFlash = "Falha ao atualizar: \(error.localizedDescription)" }
        }
    }

    @MainActor
    private func loadLinkedClinicians() async {
        guard !authToken.isEmpty, activeRole == .patient else { return }
        do {
            linkedClinicians = try await BackendAuthClient.linkedClinicians(token: authToken)
        } catch {
            linkedCliniciansStatusMessage = "Falha ao carregar profissionais vinculados: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func revokeClinicalAccess(_ clinician: BackendLinkedClinician) async {
        guard !authToken.isEmpty else { return }
        do {
            try await BackendAuthClient.revokeClinicalAccess(clinicianId: clinician.clinicianId, token: authToken)
            linkedCliniciansStatusMessage = "Acesso de \(clinician.clinicianFullName) cancelado."
            await loadLinkedClinicians()
        } catch {
            linkedCliniciansStatusMessage = "Falha ao cancelar acesso: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadPendingInvites() async {
        guard !authToken.isEmpty,
              activeRole == .patient else {
            return
        }
        do {
            pendingClinicianInvites = try await BackendAuthClient.pendingInvites(token: authToken)
        } catch {
            // Silent: banner just stays empty.
        }
    }

    @MainActor
    private func acceptInvite(_ invite: BackendClinicianInvite) async {
        guard !authToken.isEmpty else { return }
        do {
            _ = try await BackendAuthClient.acceptInvite(id: invite.id, token: authToken)
            inviteStatusMessage = "\(invite.clinicianFullName) agora acompanha você."
            await loadPendingInvites()
        } catch {
            inviteStatusMessage = "Falha ao aceitar convite: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func revokeInvite(_ invite: BackendClinicianInvite) async {
        guard !authToken.isEmpty else { return }
        do {
            _ = try await BackendAuthClient.revokeInvite(id: invite.id, token: authToken)
            inviteStatusMessage = "Convite de \(invite.clinicianFullName) recusado."
            await loadPendingInvites()
        } catch {
            inviteStatusMessage = "Falha ao recusar convite: \(error.localizedDescription)"
        }
    }

    private func applyRole(from backendRole: String) {
        let role: AccessRole = backendRole == "clinician" ? .clinician : .patient
        let patient = ensurePatient()
        patient.activeRole = role.rawValue
        // Do not overwrite consent decisions made by the user. Consent is a
        // separate, explicit action and forcing it here violates LGPD.
    }

    @MainActor
    private func linkPatientAndReload() async {
        guard !authToken.isEmpty else {
            clinicianPatientStatusMessage = "Entre como médico para vincular pacientes."
            return
        }

        do {
            let invite = try await BackendAuthClient.inviteClinicianAccess(patientEmail: patientLinkEmail, token: authToken)
            patientLinkEmail = ""
            clinicianPatientStatusMessage = "Convite enviado ao paciente (status: \(invite.status)). O vínculo só é criado após o aceite."
            await loadClinicianPatients()
            await loadClinicianSentInvites()
        } catch {
            clinicianPatientStatusMessage = "Falha ao convidar paciente: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadClinicianPatients() async {
        guard !authToken.isEmpty else {
            clinicianPatientStatusMessage = "Entre como médico para carregar pacientes."
            return
        }

        do {
            clinicianPatients = try await BackendAuthClient.clinicianPatients(token: authToken)
            clinicianPatientStatusMessage = clinicianPatients.isEmpty ? "Nenhum paciente vinculado." : "\(clinicianPatients.count) paciente(s) carregado(s)."
        } catch {
            clinicianPatientStatusMessage = "Falha ao carregar pacientes: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadRemotePatientData(_ patient: BackendUser) async {
        guard !authToken.isEmpty else {
            remotePatientStatusMessage = "Entre como médico para ver dados remotos."
            return
        }

        selectedRemotePatient = patient
        remotePatientStatusMessage = "Carregando dados de \(patient.fullName)..."
        remotePatientSubTab = .overview
        isLoadingRemotePatientData = true
        defer { isLoadingRemotePatientData = false }

        do {
            async let checkIns = BackendAuthClient.patientCheckIns(patientId: patient.id, token: authToken)
            async let assessments = BackendAuthClient.patientAssessments(patientId: patient.id, token: authToken)
            async let alerts = BackendAuthClient.patientAlerts(patientId: patient.id, token: authToken)
            async let reports = BackendAuthClient.patientReports(patientId: patient.id, token: authToken)

            remoteCheckIns = try await checkIns
            remoteAssessments = try await assessments
            remoteAlerts = try await alerts
            remoteReports = try await reports
            remotePatientStatusMessage = "Dados remotos carregados para \(patient.fullName)."
        } catch {
            remotePatientStatusMessage = "Falha ao carregar dados do paciente: \(error.localizedDescription)"
        }
    }
}

private struct SectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
    }
}

private struct StatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.orange)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct MetricOption: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

private struct AutomaticScaleResult: Identifiable {
    let id = UUID()
    let scale: ScaleKind
    let answers: [Int]
    let score: Int
    let interpretation: String
}

private struct NeuroFlowRiskSignature {
    let score: Int
    let level: ClinicalRiskLevel
    let explanation: String
    let baseline: String
    let baselineAlerts: [String]
    let similarCrisisPattern: String?
    let factors: [String]
    let focusAlerts: [String]
    let explanationDetails: [String]
    let protectiveFactors: [String]
    let predictedWindow: String

    static func calculate(
        summary: LongitudinalSummary,
        checkIns: [DailyCheckIn],
        scaleResults: [AutomaticScaleResult],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationStatus: MedicationStatus,
        activeTriggers: [String],
        textAssessment: TextRiskAssessment,
        ppgStress: Double,
        ppgQuality: Double,
        voicePauseRatio: Double,
        typingSpeed: Double,
        careFocus: CareFocus
    ) -> NeuroFlowRiskSignature {
        var points = 0.0
        var factors: [String] = []
        var protective: [String] = []
        let weights = careFocus.riskWeights
        var focusAlerts: [String] = []
        let baselineAlerts = baselineDeviationReasons(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours
        )
        let similarPattern = similarCrisisPattern(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggers
        )

        if mood <= 2 {
            points += 16 * weights.mood
            factors.append("humor baixo hoje")
        } else if mood >= 4 {
            protective.append("humor preservado")
        }

        if anxiety >= 4 {
            points += 14 * weights.anxiety
            factors.append("ansiedade alta")
        }

        if sleepHours < 6 {
            points += 12 * weights.sleep
            factors.append("sono abaixo de 6h")
        } else if sleepHours >= 7 {
            protective.append("sono adequado")
        }

        switch medicationStatus {
        case .pending:
            points += 14 * weights.medication
            factors.append("medicação pendente")
        case .partial:
            points += 8 * weights.medication
            factors.append("medicação parcial")
        case .taken:
            protective.append("medicação tomada")
        }

        if !activeTriggers.isEmpty {
            points += min(Double(activeTriggers.count) * 4 * weights.triggers, 14)
            factors.append("gatilhos ativos: \(activeTriggers.prefix(2).joined(separator: ", "))")
        }

        focusAlerts = careFocus.alerts(
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggers
        )
        if !focusAlerts.isEmpty {
            points += min(Double(focusAlerts.count) * 5, 15)
            factors.append(contentsOf: focusAlerts)
        }

        if summary.moodTrend < -0.35 {
            points += 10
            factors.append("tendência de queda do humor")
        }
        if summary.anxietyTrend > 0.35 {
            points += 10
            factors.append("tendência de aumento da ansiedade")
        }
        if summary.sleepTrend < -0.35 {
            points += 8
            factors.append("tendência de redução do sono")
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            points += 8
            factors.append("adesão longitudinal irregular")
        }

        let scaleLoad = scaleResults.reduce(0.0) { partial, result in
            partial + normalizedScaleRisk(result)
        }
        points += min(scaleLoad * 14, 18)
        if scaleLoad > 0.85 {
            factors.append("check-up automático alterado")
        }

        switch textAssessment.level {
        case .high:
            points += 24
            factors.append("sinal de segurança alto")
        case .moderate:
            points += 10
            factors.append("texto com sinal moderado")
        case .low:
            break
        }

        if ppgQuality > 0.45, ppgStress > 0.65 {
            points += 8
            factors.append("PPG sugere ativação autonômica")
        }
        if voicePauseRatio > 0.55 {
            points += 5
            factors.append("pausas de voz elevadas")
        }
        if typingSpeed > 0, typingSpeed < 25 {
            points += 4
            factors.append("digitação mais lenta no app")
        }
        if !baselineAlerts.isEmpty {
            points += min(Double(baselineAlerts.count) * 6, 18)
            factors.append(contentsOf: baselineAlerts)
        }
        if similarPattern != nil {
            points += 12
            factors.append("padrão semelhante antes de crise")
        }

        let score = Int(min(max(points, 0), 100).rounded())
        let level: ClinicalRiskLevel
        if score >= 66 || textAssessment.level == .high {
            level = .high
        } else if score >= 34 {
            level = .moderate
        } else {
            level = .low
        }

        let baseline = baselineText(checkIns: checkIns)
        let explanationDetails = detailedExplanations(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggers
        )
        let explanation = factors.isEmpty
            ? "Sem desvio relevante do padrão recente."
            : factors.prefix(4).joined(separator: " • ")
        let predictedWindow = level == .high
            ? "Atenção nas próximas 24-72h"
            : level == .moderate ? "Observar próximos 2-7 dias" : "Manter rotina e acompanhar"

        return NeuroFlowRiskSignature(
            score: score,
            level: level,
            explanation: explanation,
            baseline: baseline,
            baselineAlerts: baselineAlerts,
            similarCrisisPattern: similarPattern,
            factors: factors,
            focusAlerts: focusAlerts,
            explanationDetails: explanationDetails,
            protectiveFactors: protective,
            predictedWindow: predictedWindow
        )
    }

    private static func normalizedScaleRisk(_ result: AutomaticScaleResult) -> Double {
        switch result.scale {
        case .phq9:
            return Double(result.score) / 27
        case .gad7:
            return Double(result.score) / 21
        case .ymrs:
            return Double(result.score) / 60
        }
    }

    private static func baselineText(checkIns: [DailyCheckIn]) -> String {
        let recent = Array(checkIns.prefix(30))
        guard !recent.isEmpty else {
            return "Basal ainda em formação; registre alguns dias para personalizar."
        }

        let moodStats = stats(recent.map(\.mood))
        let anxietyStats = stats(recent.map(\.anxiety))
        let sleepStats = stats(recent.map(\.sleepHours))
        return "Basal 30 dias: humor \(format(mean: moodStats.mean, deviation: moodStats.deviation)), ansiedade \(format(mean: anxietyStats.mean, deviation: anxietyStats.deviation)), sono \(format(mean: sleepStats.mean, deviation: sleepStats.deviation))h."
    }

    private static func baselineDeviationReasons(checkIns: [DailyCheckIn], mood: Double, anxiety: Double, sleepHours: Double) -> [String] {
        let baseline = Array(checkIns.prefix(30))
        guard baseline.count >= 5 else {
            return []
        }

        var reasons: [String] = []
        let moodStats = stats(baseline.map(\.mood))
        let anxietyStats = stats(baseline.map(\.anxiety))
        let sleepStats = stats(baseline.map(\.sleepHours))

        if isMeaningfulDeviation(current: mood, mean: moodStats.mean, deviation: moodStats.deviation, direction: .lower) {
            reasons.append("humor abaixo do basal individual")
        }
        if isMeaningfulDeviation(current: anxiety, mean: anxietyStats.mean, deviation: anxietyStats.deviation, direction: .higher) {
            reasons.append("ansiedade acima do basal individual")
        }
        if isMeaningfulDeviation(current: sleepHours, mean: sleepStats.mean, deviation: sleepStats.deviation, direction: .lower) {
            reasons.append("sono abaixo do basal individual")
        }

        if progressiveDrop(values: baseline.prefix(7).map(\.sleepHours)) {
            reasons.append("sono em queda progressiva")
        }
        if progressiveRise(values: baseline.prefix(7).map(\.anxiety)) {
            reasons.append("ansiedade em alta progressiva")
        }
        if progressiveDrop(values: baseline.prefix(7).map(\.mood)) {
            reasons.append("humor em queda progressiva")
        }

        return reasons
    }

    private static func detailedExplanations(
        checkIns: [DailyCheckIn],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationStatus: MedicationStatus,
        activeTriggers: [String]
    ) -> [String] {
        var details: [String] = []
        let recent = Array(checkIns.prefix(7))
        let chronological = recent.sorted { $0.date < $1.date }

        if consecutiveSleepDropDays(in: chronological) >= 3 {
            details.append("Sono caiu por \(consecutiveSleepDropDays(in: chronological)) noites seguidas.")
        }

        if let first = chronological.first, first.anxiety > 0.1 {
            let anxietyIncrease = ((anxiety - first.anxiety) / max(first.anxiety, 0.5)) * 100
            if anxietyIncrease >= 20 {
                details.append("Ansiedade subiu \(Int(anxietyIncrease.rounded()))% em relação ao início da semana.")
            }
        }

        let incompleteMedicationDays = recent.filter { !$0.medicationTaken }.count
        if medicationStatus != .taken || incompleteMedicationDays >= 2 {
            let total = incompleteMedicationDays + (medicationStatus == .taken ? 0 : 1)
            details.append("Medicação ficou parcial/pendente em \(max(total, 1)) registro(s) recentes.")
        }

        let recentTriggers = recent.flatMap { triggerLabels(from: $0.journalEntry) } + activeTriggers.map { $0.lowercased() }
        if let commonTrigger = Dictionary(grouping: recentTriggers, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }), commonTrigger.value >= 2 {
            details.append("Gatilho \(commonTrigger.key) apareceu antes ou durante piora recente.")
        }

        if let first = chronological.first, first.mood > 0.1 {
            let moodDrop = ((first.mood - mood) / max(first.mood, 0.5)) * 100
            if moodDrop >= 20 {
                details.append("Humor caiu \(Int(moodDrop.rounded()))% em relação ao início da semana.")
            }
        }

        if sleepHours < 6 {
            details.append("Sono atual abaixo de 6h, sinal sensível para vários focos clínicos.")
        }

        return Array(details.prefix(5))
    }

    private static func consecutiveSleepDropDays(in checkIns: [DailyCheckIn]) -> Int {
        guard checkIns.count >= 3 else { return 0 }
        var streak = 1
        var best = 1
        for index in 1..<checkIns.count {
            if checkIns[index].sleepHours < checkIns[index - 1].sleepHours {
                streak += 1
                best = max(best, streak)
            } else {
                streak = 1
            }
        }
        return best >= 3 ? best : 0
    }

    private static func similarCrisisPattern(
        checkIns: [DailyCheckIn],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationStatus: MedicationStatus,
        activeTriggers: [String]
    ) -> String? {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard chronological.count >= 5 else {
            return nil
        }

        let currentVector = CrisisAntecedentVector(
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationTaken: medicationStatus == .taken,
            triggers: Set(activeTriggers.map { $0.lowercased() })
        )

        var matches: [(daysBefore: Int, score: Double, crisis: DailyCheckIn)] = []
        for index in chronological.indices {
            let crisis = chronological[index]
            guard crisis.mood <= 2 || crisis.anxiety >= 4 || crisis.suicidalIdeation else { continue }

            for offset in 1...7 {
                let antecedentIndex = chronological.index(index, offsetBy: -offset, limitedBy: chronological.startIndex)
                guard let antecedentIndex else { continue }

                let antecedent = chronological[antecedentIndex]
                let vector = CrisisAntecedentVector(
                    mood: antecedent.mood,
                    anxiety: antecedent.anxiety,
                    sleepHours: antecedent.sleepHours,
                    medicationTaken: antecedent.medicationTaken,
                    triggers: Set(triggerLabels(from: antecedent.journalEntry))
                )
                let score = currentVector.similarity(to: vector)
                if score >= 0.72 {
                    matches.append((offset, score, crisis))
                }
            }
        }

        guard let best = matches.max(by: { $0.score < $1.score }) else {
            return nil
        }

        let percent = Int((best.score * 100).rounded())
        return "Padrão \(percent)% parecido apareceu \(best.daysBefore) dia(s) antes de um dia ruim anterior."
    }

    private static func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }

    private enum DeviationDirection {
        case higher
        case lower
    }

    private static func isMeaningfulDeviation(current: Double, mean: Double, deviation: Double, direction: DeviationDirection) -> Bool {
        let safeDeviation = max(deviation, 0.35)
        switch direction {
        case .higher:
            return current >= mean + safeDeviation
        case .lower:
            return current <= mean - safeDeviation
        }
    }

    private static func stats(_ values: [Double]) -> (mean: Double, deviation: Double) {
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return (mean, sqrt(variance))
    }

    private static func format(mean: Double, deviation: Double) -> String {
        "\(String(format: "%.1f", mean))±\(String(format: "%.1f", deviation))"
    }

    private static func progressiveDrop(values: [Double]) -> Bool {
        let ordered = Array(values.reversed())
        guard ordered.count >= 5 else { return false }
        return (ordered.last ?? 0) <= (ordered.first ?? 0) - 0.8
    }

    private static func progressiveRise(values: [Double]) -> Bool {
        let ordered = Array(values.reversed())
        guard ordered.count >= 5 else { return false }
        return (ordered.last ?? 0) >= (ordered.first ?? 0) + 0.8
    }
}

private struct CrisisAntecedentVector {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let medicationTaken: Bool
    let triggers: Set<String>

    func similarity(to other: CrisisAntecedentVector) -> Double {
        let moodScore = closeness(mood, other.mood, range: 4)
        let anxietyScore = closeness(anxiety, other.anxiety, range: 4)
        let sleepScore = closeness(sleepHours, other.sleepHours, range: 8)
        let medicationScore = medicationTaken == other.medicationTaken ? 1.0 : 0.0
        let triggerScore = triggerSimilarity(to: other)
        return moodScore * 0.24
            + anxietyScore * 0.24
            + sleepScore * 0.22
            + medicationScore * 0.14
            + triggerScore * 0.16
    }

    private func closeness(_ first: Double, _ second: Double, range: Double) -> Double {
        max(0, 1 - abs(first - second) / range)
    }

    private func triggerSimilarity(to other: CrisisAntecedentVector) -> Double {
        if triggers.isEmpty && other.triggers.isEmpty {
            return 1
        }
        let intersection = triggers.intersection(other.triggers).count
        let union = triggers.union(other.triggers).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}

private enum PatientPage: String, CaseIterable, Identifiable {
    case diary = "Hoje"
    // P1-4 (UX): "Corpo" renomeado para "Sinais" — o conteúdo real é
    // medição fisiológica (PPG/câmera, HRV, Apple Health), não "corpo" no
    // sentido amplo. "Sinais" comunica a funcionalidade diretamente.
    case bodySignals = "Sinais"
    case evolution = "Evolução"
    // P1-4 (UX): ícone "briefcase" (maleta de trabalho) trocado por
    // "heart.text.clipboard" que comunica cuidado de saúde.
    case tools = "Ferramentas"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .diary:
            "house.fill"
        case .bodySignals:
            "waveform.path.ecg"
        case .evolution:
            "chart.line.uptrend.xyaxis"
        case .tools:
            "heart.text.clipboard"
        }
    }
}

// `PatientPageSelector` foi removido na Sprint 20 — a TabView raiz (Sprint 19)
// substituiu o segmented picker. O enum PatientPage continua sendo a fonte
// canônica para `selectedPatientPage` (controla qual aba está ativa).

// Sprint 25: filtro de tipo de evento para a Tab Evolução.
private enum EvolutionFilter: String, CaseIterable, Identifiable {
    case all = "Tudo"
    case checkIns = "Check-ins"
    case scales = "Escalas"
    case alerts = "Alertas"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .checkIns: "calendar"
        case .scales: "list.clipboard"
        case .alerts: "bell.badge"
        }
    }
}

// MARK: - Tipos do dashboard médico (Sprint 24)

private enum ClinicianPatientFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case highRisk = "Alto risco"
    case alphabetical = "Por nome"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .highRisk: "exclamationmark.triangle.fill"
        case .alphabetical: "textformat"
        }
    }
}

private enum SentInviteStatusFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case pending = "Pendentes"
    case accepted = "Aceitos"
    case revoked = "Recusados"
    var id: String { rawValue }
    var apiStatus: String? {
        switch self {
        case .all: return nil
        case .pending: return "pending"
        case .accepted: return "accepted"
        case .revoked: return "revoked"
        }
    }
}

// P1-2 (UX): níveis de toast centralizados. .error não auto-dismiss.
private enum ToastLevel {
    case success, warning, error
    var color: Color {
        switch self { case .success: .green; case .warning: .orange; case .error: .red }
    }
    var icon: String {
        switch self { case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .error: "xmark.octagon.fill" }
    }
    /// nil = não faz auto-dismiss
    var autoDismissSeconds: Double? {
        switch self { case .success: 2; case .warning: 4; case .error: nil }
    }
}

// M5 (UX-P0): abas do dashboard do clínico — substitui o scroll único.
private enum ClinicianTab: String, CaseIterable, Identifiable {
    case patients = "Pacientes"
    case analysis = "Análise"
    case reports  = "Relatórios"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .patients: "person.2"
        case .analysis: "chart.xyaxis.line"
        case .reports:  "doc.text.magnifyingglass"
        }
    }
}

private enum RemotePatientSubTab: String, CaseIterable, Identifiable {
    case overview = "Visão geral"
    case checkIns = "Diário"
    case assessments = "Escalas"
    case alerts = "Alertas"
    case reports = "Relatórios"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "person.text.rectangle"
        case .checkIns: "list.bullet.rectangle"
        case .assessments: "list.clipboard"
        case .alerts: "bell.badge"
        case .reports: "doc.text"
        }
    }
}

private enum MedicationStatus: String, CaseIterable, Identifiable {
    case pending = "Pendente"
    case partial = "Parcial"
    case taken = "Tomada"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .pending:
            "⏰"
        case .partial:
            "🌓"
        case .taken:
            "✅"
        }
    }

    var subtitle: String {
        switch self {
        case .pending:
            "Ainda não tomei"
        case .partial:
            "Tomei parte da medicação"
        case .taken:
            "Tomada hoje"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            .orange
        case .partial:
            .neuroYellow
        case .taken:
            .green
        }
    }
}

private enum SafetyStatus: String, CaseIterable, Identifiable {
    case safe = "Seguro"
    case attention = "Atenção"
    case urgent = "Apoio"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .safe:
            "🛟"
        case .attention:
            "🟡"
        case .urgent:
            "🆘"
        }
    }

    var subtitle: String {
        switch self {
        case .safe:
            "Sem pensamentos de me machucar"
        case .attention:
            "Pensamentos difíceis, mas sem risco imediato"
        case .urgent:
            "Preciso de apoio agora"
        }
    }

    var color: Color {
        switch self {
        case .safe:
            .green
        case .attention:
            .orange
        case .urgent:
            .red
        }
    }
}

private enum CareFocus: String, CaseIterable, Identifiable {
    case bipolar = "Bipolaridade"
    case depression = "Depressão"
    case anxiety = "Ansiedade"
    case borderline = "Borderline"
    case burnout = "Burnout"
    case adhd = "TDAH"
    case postpartum = "Pós-parto"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bipolar:
            "arrow.triangle.2.circlepath"
        case .depression:
            "cloud.rain.fill"
        case .anxiety:
            "waveform.path.ecg"
        case .borderline:
            "person.2.wave.2.fill"
        case .burnout:
            "flame.fill"
        case .adhd:
            "target"
        case .postpartum:
            "heart.text.square.fill"
        }
    }

    var description: String {
        switch self {
        case .bipolar:
            "Prioriza sono, energia, irritabilidade, medicação e sinais de virada de humor."
        case .depression:
            "Prioriza humor, energia, sono, apetite, adesão e sinais de desesperança."
        case .anxiety:
            "Prioriza ansiedade, sono, gatilhos, pensamentos repetitivos e tensão diária."
        case .borderline:
            "Prioriza intensidade emocional, gatilhos interpessoais e segurança."
        case .burnout:
            "Prioriza energia, sono, estresse, rotina e recuperação."
        case .adhd:
            "Prioriza energia, rotina, sono, adesão e impacto funcional."
        case .postpartum:
            "Prioriza sono, humor, ansiedade, apoio e sinais de alerta no pós-parto."
        }
    }

    var modules: String {
        switch self {
        case .bipolar:
            "Sono, energia, irritabilidade, YMRS, adesão e gatilhos de virada."
        case .depression:
            "PHQ-9, humor, energia, sono, apetite e segurança."
        case .anxiety:
            "GAD-7, ansiedade, sono, gatilhos e pensamentos repetitivos."
        case .borderline:
            "Intensidade emocional, conflitos, impulsividade e plano de segurança."
        case .burnout:
            "Energia, estresse, sono, recuperação e rotina."
        case .adhd:
            "Rotina, sono, energia, adesão e impacto funcional."
        case .postpartum:
            "Humor, ansiedade, sono, rede de apoio e sinais de alerta."
        }
    }

    var dsm5MonitoringFrame: String {
        switch self {
        case .bipolar:
            "No DSM-5/DSM-5-TR, transtornos bipolares envolvem episódios de elevação/expansividade ou irritabilidade do humor, alterações de energia/atividade e impacto funcional. Por isso o app acompanha sono, energia, irritabilidade, humor, impulsividade indireta, adesão e sinais de virada."
        case .depression:
            "O enquadramento DSM-5/DSM-5-TR para quadros depressivos valoriza duração, sofrimento/impacto funcional e um conjunto de sintomas afetivos, cognitivos, vegetativos e de segurança. Por isso o app observa humor, energia, sono, apetite, pensamentos negativos e risco de autoagressão."
        case .anxiety:
            "No DSM-5/DSM-5-TR, transtornos de ansiedade envolvem medo/ansiedade persistentes, preocupação, sintomas físicos e prejuízo funcional. Por isso o app monitora ansiedade diária, sono, gatilhos, pensamentos repetitivos, ativação corporal e evitação indireta."
        case .borderline:
            "O DSM-5/DSM-5-TR descreve transtornos de personalidade a partir de padrões persistentes de funcionamento, relações, impulsividade e regulação emocional. Por isso o app observa intensidade emocional, conflitos, segurança, gatilhos interpessoais e padrões repetidos ao longo do tempo."
        case .burnout:
            "Burnout não é uma categoria diagnóstica principal do DSM-5/DSM-5-TR; é acompanhado aqui como estado relacionado a estresse, exaustão, sono e funcionamento. O app usa esse módulo para monitoramento funcional, não para diagnóstico."
        case .adhd:
            "O DSM-5/DSM-5-TR entende TDAH como padrão persistente de desatenção e/ou hiperatividade-impulsividade com impacto em múltiplos contextos. Por isso o app acompanha rotina, sono, adesão, energia, funcionamento e consistência diária."
        case .postpartum:
            "O DSM-5/DSM-5-TR permite especificadores periparto para alguns quadros de humor. O app trata pós-parto como contexto clínico de maior vulnerabilidade, priorizando sono, humor, ansiedade, rede de apoio e sinais de segurança."
        }
    }

    var dsm5SignalSummary: [String] {
        switch self {
        case .bipolar:
            ["sono reduzido", "energia elevada ou queda brusca", "irritabilidade", "adesão medicamentosa", "YMRS como escala auxiliar"]
        case .depression:
            ["humor deprimido", "perda de energia", "sono/apetite alterados", "pensamentos negativos", "PHQ-9 como escala auxiliar"]
        case .anxiety:
            ["ansiedade persistente", "preocupação", "sono ruim", "gatilhos", "GAD-7 como escala auxiliar"]
        case .borderline:
            ["intensidade emocional", "conflitos", "impulsividade indireta", "segurança", "padrões repetidos"]
        case .burnout:
            ["exaustão", "recuperação ruim", "estresse", "sono", "impacto funcional"]
        case .adhd:
            ["rotina", "atenção indireta", "adesão", "sono", "funcionamento diário"]
        case .postpartum:
            ["sono fragmentado", "humor", "ansiedade", "apoio", "segurança"]
        }
    }

    var dsm5CriteriaGroups: [DSM5CriteriaGroup] {
        switch self {
        case .bipolar:
            [
                DSM5CriteriaGroup(
                    title: "Episódio de elevação ou irritabilidade",
                    items: ["humor anormalmente elevado, expansivo ou irritável", "aumento de energia ou atividade", "mudança clara em relação ao funcionamento habitual"]
                ),
                DSM5CriteriaGroup(
                    title: "Sinais associados",
                    items: ["menor necessidade de sono", "fala ou pensamentos acelerados", "impulsividade, agitação ou aumento de metas", "autoestima inflada ou distraibilidade"]
                ),
                DSM5CriteriaGroup(
                    title: "Impacto e exclusões",
                    items: ["prejuízo funcional, internação, psicose ou risco relevante", "avaliar substâncias, medicações, sono e condições clínicas", "diferenciar mania, hipomania, depressão e estados mistos"]
                )
            ]
        case .depression:
            [
                DSM5CriteriaGroup(
                    title: "Humor e interesse",
                    items: ["humor deprimido persistente", "perda de interesse ou prazer", "sofrimento clinicamente significativo"]
                ),
                DSM5CriteriaGroup(
                    title: "Sintomas cognitivos e vegetativos",
                    items: ["alterações de sono, apetite ou peso", "fadiga ou lentificação/agitação", "culpa, desesperança ou baixa autoestima", "concentração reduzida ou pensamentos de morte"]
                ),
                DSM5CriteriaGroup(
                    title: "Duração e contexto",
                    items: ["verificar persistência temporal", "avaliar prejuízo social, ocupacional ou familiar", "excluir luto, substâncias, bipolaridade e causas médicas"]
                )
            ]
        case .anxiety:
            [
                DSM5CriteriaGroup(
                    title: "Medo, ansiedade ou preocupação",
                    items: ["ansiedade persistente ou difícil de controlar", "preocupação excessiva", "hipervigilância ou sensação de ameaça"]
                ),
                DSM5CriteriaGroup(
                    title: "Ativação e evitação",
                    items: ["tensão, inquietação ou sintomas físicos", "sono prejudicado", "evitação de situações ou gatilhos", "dificuldade de concentração"]
                ),
                DSM5CriteriaGroup(
                    title: "Impacto e diferenciais",
                    items: ["confirmar prejuízo funcional", "avaliar pânico, fobias, trauma e obsessões", "considerar substâncias, cafeína, tireoide e outras causas clínicas"]
                )
            ]
        case .borderline:
            [
                DSM5CriteriaGroup(
                    title: "Padrão interpessoal e emocional",
                    items: ["instabilidade de relacionamentos", "medo intenso de abandono", "oscilações afetivas rápidas"]
                ),
                DSM5CriteriaGroup(
                    title: "Impulsividade e segurança",
                    items: ["impulsividade com potencial dano", "raiva intensa ou dificuldade de controle", "autoagressão, ameaças ou ideação suicida", "sensação de vazio ou identidade instável"]
                ),
                DSM5CriteriaGroup(
                    title: "Persistência e contexto",
                    items: ["padrão duradouro em múltiplos contextos", "diferenciar de episódios de humor, trauma e uso de substâncias", "avaliar risco atual antes de qualquer conclusão diagnóstica"]
                )
            ]
        case .burnout:
            [
                DSM5CriteriaGroup(
                    title: "Não é diagnóstico DSM-5 principal",
                    items: ["monitorar como contexto de estresse ocupacional", "avaliar exaustão, cinismo e queda de eficácia", "investigar impacto no sono, humor e funcionamento"]
                ),
                DSM5CriteriaGroup(
                    title: "Triagem relacionada",
                    items: ["diferenciar de depressão, ansiedade e transtornos do sono", "identificar sobrecarga, falta de recuperação e gatilhos de trabalho", "observar risco de autonegligência ou ideação suicida"]
                )
            ]
        case .adhd:
            [
                DSM5CriteriaGroup(
                    title: "Desatenção e/ou hiperatividade-impulsividade",
                    items: ["dificuldade persistente de atenção ou organização", "inquietação, impulsividade ou dificuldade de esperar", "inconsistência em tarefas e rotina"]
                ),
                DSM5CriteriaGroup(
                    title: "Curso e contextos",
                    items: ["sinais desde o desenvolvimento", "presença em mais de um ambiente", "prejuízo acadêmico, profissional, social ou doméstico"]
                ),
                DSM5CriteriaGroup(
                    title: "Diferenciais",
                    items: ["avaliar sono, ansiedade, depressão e uso de substâncias", "considerar efeitos de medicação e condições clínicas", "integrar relato do paciente e informantes quando possível"]
                )
            ]
        case .postpartum:
            [
                DSM5CriteriaGroup(
                    title: "Contexto periparto",
                    items: ["relacionar início dos sintomas ao ciclo gestacional/pós-parto", "monitorar humor, ansiedade, sono e apoio", "verificar sofrimento e prejuízo funcional"]
                ),
                DSM5CriteriaGroup(
                    title: "Segurança materna e do bebê",
                    items: ["avaliar pensamentos de autoagressão", "avaliar pensamentos de dano ao bebê sem julgamento", "identificar psicose, confusão, agitação grave ou risco imediato"]
                ),
                DSM5CriteriaGroup(
                    title: "Diferenciais",
                    items: ["distinguir tristeza pós-parto transitória de quadro persistente", "considerar bipolaridade, depressão, ansiedade e trauma", "acionar rede de apoio e avaliação urgente quando houver risco"]
                )
            ]
        }
    }

    var preferredScale: ScaleKind {
        switch self {
        case .bipolar:
            .ymrs
        case .depression, .borderline, .burnout, .postpartum:
            .phq9
        case .anxiety, .adhd:
            .gad7
        }
    }

    var riskWeights: CareFocusRiskWeights {
        switch self {
        case .bipolar:
            CareFocusRiskWeights(mood: 1.05, anxiety: 0.95, sleep: 1.45, medication: 1.25, triggers: 1.10)
        case .depression:
            CareFocusRiskWeights(mood: 1.35, anxiety: 0.95, sleep: 1.10, medication: 1.05, triggers: 1.00)
        case .anxiety:
            CareFocusRiskWeights(mood: 0.95, anxiety: 1.40, sleep: 1.15, medication: 1.00, triggers: 1.20)
        case .borderline:
            CareFocusRiskWeights(mood: 1.15, anxiety: 1.15, sleep: 1.00, medication: 1.00, triggers: 1.45)
        case .burnout:
            CareFocusRiskWeights(mood: 1.00, anxiety: 1.05, sleep: 1.25, medication: 0.90, triggers: 1.20)
        case .adhd:
            CareFocusRiskWeights(mood: 0.90, anxiety: 1.00, sleep: 1.20, medication: 1.35, triggers: 1.00)
        case .postpartum:
            CareFocusRiskWeights(mood: 1.25, anxiety: 1.25, sleep: 1.35, medication: 1.00, triggers: 1.10)
        }
    }

    func alerts(mood: Double, anxiety: Double, sleepHours: Double, medicationStatus: MedicationStatus, activeTriggers: [String]) -> [String] {
        var alerts: [String] = []
        switch self {
        case .bipolar:
            if sleepHours < 5 { alerts.append("bipolaridade: sono muito reduzido") }
            if mood >= 4 && sleepHours < 6 { alerts.append("bipolaridade: energia/humor alto com pouco sono") }
        case .depression:
            if mood <= 2 { alerts.append("depressão: queda de humor relevante") }
            if sleepHours > 9 || sleepHours < 5 { alerts.append("depressão: sono muito alterado") }
        case .anxiety:
            if anxiety >= 4 { alerts.append("ansiedade: ativação intensa") }
            if !activeTriggers.isEmpty { alerts.append("ansiedade: gatilhos ativos") }
        case .borderline:
            if activeTriggers.contains(where: { $0.localizedCaseInsensitiveContains("conflito") }) { alerts.append("borderline: gatilho interpessoal") }
            if anxiety >= 4 || mood <= 2 { alerts.append("borderline: intensidade emocional alta") }
        case .burnout:
            if mood <= 2 || sleepHours < 6 { alerts.append("burnout: exaustão/recuperação ruim") }
        case .adhd:
            if medicationStatus != .taken { alerts.append("TDAH: adesão medicamentosa incompleta") }
            if sleepHours < 6 { alerts.append("TDAH: sono reduzido pode piorar funcionamento") }
        case .postpartum:
            if sleepHours < 5 { alerts.append("pós-parto: privação de sono relevante") }
            if mood <= 2 || anxiety >= 4 { alerts.append("pós-parto: humor/ansiedade exige atenção") }
        }
        return alerts
    }

    var safetyGuidance: String {
        switch self {
        case .bipolar:
            "Se o sono cair ou houver aceleração, reduzir estímulos e avisar o profissional."
        case .depression:
            "Se houver desesperança ou risco de se machucar, acionar apoio imediatamente."
        case .anxiety:
            "Usar estratégias de aterramento, respiração e reduzir exposição ao gatilho."
        case .borderline:
            "Priorizar contato de apoio, adiar decisões impulsivas e usar estratégia combinada."
        case .burnout:
            "Reduzir demanda, proteger sono e planejar recuperação nas próximas 24h."
        case .adhd:
            "Checar medicação, rotina do dia e reduzir fricção para tarefas essenciais."
        case .postpartum:
            "Acionar rede de apoio, proteger sono e procurar ajuda se sintomas intensificarem."
        }
    }
}

private struct CareFocusRiskWeights {
    let mood: Double
    let anxiety: Double
    let sleep: Double
    let medication: Double
    let triggers: Double
}

private struct MoodWheelCard: View {
    @Binding var mood: Double
    @Binding var anxiety: Double
    @Binding var energy: Double

    private let emotions: [MoodWheelEmotion] = [
        MoodWheelEmotion(emoji: "😊", title: "Leve", mood: 5, anxiety: 1, energy: 4, color: .green),
        MoodWheelEmotion(emoji: "🙂", title: "Bem", mood: 4, anxiety: 2, energy: 3, color: .neuroYellow),
        MoodWheelEmotion(emoji: "😐", title: "Neutro", mood: 3, anxiety: 2, energy: 3, color: .gray),
        MoodWheelEmotion(emoji: "😟", title: "Ansioso", mood: 2, anxiety: 4, energy: 3, color: .orange),
        MoodWheelEmotion(emoji: "😔", title: "Triste", mood: 1, anxiety: 3, energy: 1, color: .blue),
        MoodWheelEmotion(emoji: "😠", title: "Irritado", mood: 2, anxiety: 4, energy: 4, color: .red)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Como você está agora?")
                        .font(.headline)
                    Text("Toque em uma emoção ou ajuste os sliders abaixo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(currentEmoji)
                    .font(.largeTitle)
            }

            CircularMoodWheel(emotions: emotions, mood: $mood, anxiety: $anxiety, energy: $energy)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.neuroYellow.opacity(0.28), Color.neuroGold.opacity(0.12), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.neuroGold.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var currentEmoji: String {
        if mood >= 4 && anxiety <= 2 { return "😊" }
        if mood <= 1.5 { return "😔" }
        if anxiety >= 4 { return "😟" }
        return "🙂"
    }

}

private struct MoodWheelEmotion: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let mood: Double
    let anxiety: Double
    let energy: Double
    let color: Color
}

private struct CircularMoodWheel: View {
    let emotions: [MoodWheelEmotion]
    @Binding var mood: Double
    @Binding var anxiety: Double
    @Binding var energy: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(.systemBackground), Color.neuroYellow.opacity(0.22)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 132
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.neuroYellow, .neuroGold, .neuroOrange, .red, .blue, .green, .neuroYellow],
                                center: .center
                            ),
                            lineWidth: 5
                        )
                }
                .shadow(color: .orange.opacity(0.14), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text(selectedEmoji)
                    .font(.system(size: 44))
                Text(selectedTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(Circle())

            ForEach(Array(emotions.enumerated()), id: \.element.id) { index, emotion in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        mood = emotion.mood
                        anxiety = emotion.anxiety
                        energy = emotion.energy
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(emotion.emoji)
                            .font(.title)
                        Text(emotion.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 76, height: 62)
                    .background(isSelected(emotion) ? emotion.color.opacity(0.24) : Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected(emotion) ? emotion.color : Color.clear, lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .scaleEffect(isSelected(emotion) ? 1.08 : 1)
                    .shadow(color: isSelected(emotion) ? emotion.color.opacity(0.24) : .clear, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .offset(offset(for: index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 270)
    }

    private var selectedEmoji: String {
        emotions.first(where: { isSelected($0) })?.emoji ?? "🙂"
    }

    private var selectedTitle: String {
        emotions.first(where: { isSelected($0) })?.title ?? "Hoje"
    }

    private func isSelected(_ emotion: MoodWheelEmotion) -> Bool {
        abs(mood - emotion.mood) < 0.1 && abs(anxiety - emotion.anxiety) < 0.1
    }

    private func offset(for index: Int) -> CGSize {
        let angle = (Double(index) / Double(max(emotions.count, 1))) * 2 * Double.pi - Double.pi / 2
        let radius = 96.0
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

private struct PatientEvolutionCard: View {
    let checkIns: [DailyCheckIn]
    let currentMood: Double
    let currentAnxiety: Double
    let currentIrritability: Double
    let currentSleep: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "chart.line.uptrend.xyaxis", title: "Minha evolução")

            Text("Um resumo simples para perceber mudanças antes que elas acumulem.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                MiniTrendCard(title: "Humor", icon: "face.smiling", values: recentValues(\.mood, fallback: currentMood), color: .neuroYellow, maxValue: 5)
                MiniTrendCard(title: "Ansiedade", icon: "waveform.path.ecg", values: recentValues(\.anxiety, fallback: currentAnxiety), color: .orange, maxValue: 5)
                MiniTrendCard(title: "Irritabilidade", icon: "exclamationmark.bubble", values: recentValues(\.irritability, fallback: currentIrritability), color: .red, maxValue: 5)
                MiniTrendCard(title: "Sono", icon: "moon.zzz", values: recentValues(\.sleepHours, fallback: currentSleep), color: .indigo, maxValue: 10)
            }
        }
        .panelStyle()
    }

    private func recentValues(_ keyPath: KeyPath<DailyCheckIn, Double>, fallback: Double) -> [Double] {
        let values = checkIns.prefix(7).reversed().map { $0[keyPath: keyPath] }
        return values.isEmpty ? [fallback] : values
    }
}

private struct NeuroFlowRiskSignatureCard: View {
    let signature: NeuroFlowRiskSignature

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(icon: "brain.head.profile", title: "Como você está em geral")
                    Text("Score próprio experimental, calculado a partir dos registros e sinais do app. As escalas oficiais continuam separadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(signature.score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(signature.level.rawValue)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(levelColor)
            }

            // P2-4 (UX): faixas de interpretação com ticks e labels abaixo
            // da barra — sem eles "34 pontos" não é interpretável para o
            // paciente. Leve 0-33 | Moderado 34-65 | Alto 66-100.
            VStack(spacing: 4) {
                ProgressView(value: Double(signature.score), total: 100)
                    .tint(levelColor)

                HStack(spacing: 0) {
                    Text("Leve")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Moderado")
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("Alto")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Text(signature.explanation)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Label(signature.predictedWindow, systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(levelColor)

            Text(signature.baseline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !signature.baselineAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Desvio do seu padrão")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(signature.baselineAlerts.prefix(4), id: \.self) { alert in
                        Label(alert.capitalized, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.caption)
                            .foregroundStyle(levelColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(levelColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let similarCrisisPattern = signature.similarCrisisPattern {
                Label(similarCrisisPattern, systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(levelColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !signature.explanationDetails.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Por que o score mudou")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(signature.explanationDetails, id: \.self) { detail in
                        Label(detail, systemImage: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !signature.protectiveFactors.isEmpty {
                Text("Proteções: \(signature.protectiveFactors.prefix(3).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private var levelColor: Color {
        switch signature.level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

private struct PatientPatternInsightCard: View {
    let checkIns: [DailyCheckIn]
    let medicationPlans: [MedicationPlanEntry]
    let summary: LongitudinalSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "sparkles.rectangle.stack", title: "Padrões precoces")

            Text("O app cruza diário, sono, sintomas, medicação e gatilhos para sugerir hipóteses de acompanhamento. Não é diagnóstico automático.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                InsightTile(icon: "arrow.down.right.circle", title: "O que está mudando", text: worseningInsight, tint: .orange)
                InsightTile(icon: "moon.zzz", title: "Sono x ansiedade", text: sleepBeforeAnxietyInsight, tint: .indigo)
                InsightTile(icon: "exclamationmark.triangle", title: "Antes de dias ruins", text: triggerInsight, tint: .red)
                InsightTile(icon: "arrow.triangle.branch", title: "Padrão parecido", text: similarAntecedentInsight, tint: .purple)
                InsightTile(icon: "pills", title: "Medicação x resposta", text: medicationInsight, tint: .green)
            }
        }
        .panelStyle()
    }

    private var worseningInsight: String {
        var findings: [String] = []
        if summary.moodTrend < -0.25 {
            findings.append("humor em queda")
        }
        if summary.anxietyTrend > 0.25 {
            findings.append("ansiedade em alta")
        }
        if summary.sleepTrend < -0.25 {
            findings.append("sono reduzindo")
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            findings.append("adesão irregular")
        }
        return findings.isEmpty ? "Sem piora consistente nos registros recentes." : findings.joined(separator: ", ").capitalized + "."
    }

    private var sleepBeforeAnxietyInsight: String {
        let chronological = checkIns.sorted { $0.date < $1.date }
        let pairs = zip(chronological, chronological.dropFirst())
        let matches = pairs.filter { previous, current in
            previous.sleepHours < 6 && current.anxiety >= 4
        }
        if matches.isEmpty {
            return "Ainda não há padrão claro de pouco sono antes de ansiedade alta."
        }
        return "Pouco sono apareceu antes de ansiedade alta em \(matches.count) registro(s)."
    }

    private var triggerInsight: String {
        let riskyDays = checkIns.filter { $0.mood <= 2 || $0.anxiety >= 4 || $0.suicidalIdeation }
        let triggers = riskyDays.flatMap { triggerLabels(from: $0.journalEntry) }
        guard let mostCommon = mostFrequent(in: triggers) else {
            return "Com mais histórico, o app identifica gatilhos antes de dias ruins."
        }
        return "\(mostCommon) apareceu com mais frequência antes de dias de maior sofrimento."
    }

    private var medicationInsight: String {
        let changes = medicationPlans
            .map(\.changeNote)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !changes.isEmpty {
            return "Há mudança de dose/medicação registrada. Compare os próximos dias com humor, sono e ansiedade."
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            return "Adesão abaixo de 80%; vale observar relação com sintomas e efeitos colaterais."
        }
        return "Sem mudança de dose registrada nos dados locais."
    }

    private var similarAntecedentInsight: String {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard chronological.count >= 5, let latest = chronological.last else {
            return "Com mais histórico, o app compara o dia atual com padrões antes de crises anteriores."
        }

        let currentVector = CrisisAntecedentVector(
            mood: latest.mood,
            anxiety: latest.anxiety,
            sleepHours: latest.sleepHours,
            medicationTaken: latest.medicationTaken,
            triggers: Set(triggerLabels(from: latest.journalEntry))
        )
        var bestMatch: (daysBefore: Int, score: Double)?

        for index in chronological.indices {
            let crisis = chronological[index]
            guard crisis.mood <= 2 || crisis.anxiety >= 4 || crisis.suicidalIdeation else { continue }

            for offset in 1...7 {
                guard let antecedentIndex = chronological.index(index, offsetBy: -offset, limitedBy: chronological.startIndex) else {
                    continue
                }
                let antecedent = chronological[antecedentIndex]
                guard antecedent.date < latest.date else { continue }
                let antecedentVector = CrisisAntecedentVector(
                    mood: antecedent.mood,
                    anxiety: antecedent.anxiety,
                    sleepHours: antecedent.sleepHours,
                    medicationTaken: antecedent.medicationTaken,
                    triggers: Set(triggerLabels(from: antecedent.journalEntry))
                )
                let score = currentVector.similarity(to: antecedentVector)
                if score >= 0.72, score > (bestMatch?.score ?? 0) {
                    bestMatch = (offset, score)
                }
            }
        }

        guard let bestMatch else {
            return "Ainda não há episódio passado parecido o suficiente para comparação."
        }

        return "Hoje parece \(Int((bestMatch.score * 100).rounded()))% com um padrão que ocorreu \(bestMatch.daysBefore) dia(s) antes de piora anterior."
    }

    private func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }

    private func mostFrequent(in values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 })
            .mapValues(\.count)
            .max { $0.value < $1.value }?
            .key
    }
}

private struct InsightTile: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AppointmentEventCard: View {
    @Binding var appointmentDate: Date
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "calendar.badge.clock", title: "Próxima consulta")

            DatePicker("Data da consulta", selection: $appointmentDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)

            TextField("Observação para lembrar na consulta", text: $note)
                .textFieldStyle(.roundedBorder)

            Text("A consulta registrada aparece como evento na linha do tempo clínica.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct ClinicalTimelineCard: View {
    let checkIns: [DailyCheckIn]
    let medicationPlans: [MedicationPlanEntry]
    let appointmentDate: Date
    let appointmentNote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "timeline.selection", title: "Linha do tempo clínica")

            if events.isEmpty {
                EmptyState(text: "Com mais registros, eventos importantes aparecem aqui automaticamente.")
            } else {
                ForEach(events.prefix(8)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.icon)
                            .foregroundStyle(event.color)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(event.color.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }

    private var events: [ClinicalTimelineEvent] {
        var items: [ClinicalTimelineEvent] = []

        items.append(
            ClinicalTimelineEvent(
                date: appointmentDate,
                icon: "calendar.badge.clock",
                title: "Consulta agendada",
                detail: appointmentNote.isEmpty ? appointmentDate.formatted(date: .abbreviated, time: .shortened) : appointmentNote,
                color: .blue
            )
        )

        for plan in medicationPlans where !plan.changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(ClinicalTimelineEvent(date: plan.createdAt, icon: "pills", title: "Mudança de medicação", detail: plan.changeNote, color: .green))
        }

        for checkIn in checkIns {
            if checkIn.suicidalIdeation {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "exclamationmark.triangle", title: "Sinal de segurança", detail: "Triagem marcou necessidade de atenção imediata.", color: .red))
            } else if checkIn.mood <= 2 || checkIn.anxiety >= 4 {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "waveform.path.ecg", title: "Dia de maior sofrimento", detail: "Humor \(String(format: "%.0f", checkIn.mood))/5, ansiedade \(String(format: "%.0f", checkIn.anxiety))/5.", color: .orange))
            }

            if !checkIn.medicationTaken {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "pills.circle", title: "Medicação pendente/parcial", detail: "Registro de adesão incompleta no dia.", color: .orange))
            }

            if checkIn.sleepHours < 6 {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "moon.zzz", title: "Alteração de sono", detail: "Sono registrado abaixo de 6 horas.", color: .indigo))
            }

            if checkIn.mood >= 4 && checkIn.anxiety <= 2 && checkIn.sleepHours >= 7 {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "checkmark.seal", title: "Dia de estabilidade", detail: "Humor preservado, ansiedade baixa e sono adequado.", color: .green))
            }
        }

        return items.sorted { $0.date > $1.date }
    }
}

private struct ClinicalTimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let icon: String
    let title: String
    let detail: String
    let color: Color
}

private struct DigitalPhenotypeCard: View {
    let checkIns: [DailyCheckIn]
    let medicationPlans: [MedicationPlanEntry]
    let signature: NeuroFlowRiskSignature
    let ppgStress: Double
    let ppgQuality: Double
    let voicePauseRatio: Double
    let typingSpeed: Double
    let healthSleepHours: Double
    let healthSteps: Int
    let healthHeartRate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.text.rectangle", title: "Fenótipo digital")

            Text("Perfil longitudinal individual, ainda experimental, para entender padrões próprios do paciente.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                InsightTile(icon: "moon.zzz", title: "Sono típico", text: sleepPattern, tint: .indigo)
                InsightTile(icon: "waveform.path.ecg", title: "Ansiedade típica", text: anxietyPattern, tint: .orange)
                InsightTile(icon: "tag", title: "Gatilho recorrente", text: triggerPattern, tint: .red)
                InsightTile(icon: "pills", title: "Resposta à medicação", text: medicationPattern, tint: .green)
                InsightTile(icon: "heart.circle", title: "PPG", text: ppgPattern, tint: .pink)
                InsightTile(icon: "mic.circle", title: "Voz", text: voicePattern, tint: .purple)
                InsightTile(icon: "keyboard", title: "Digitação", text: typingPattern, tint: .teal)
                InsightTile(icon: "figure.walk.circle", title: "Apple Health", text: healthPattern, tint: .blue)
            }

            Text("Assinatura atual: \(signature.level.rawValue.lowercased()) (\(signature.score)/100).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var sleepPattern: String {
        guard !checkIns.isEmpty else { return "Ainda sem histórico suficiente." }
        let average = checkIns.prefix(14).map(\.sleepHours).reduce(0, +) / Double(min(checkIns.count, 14))
        return "Média recente de \(String(format: "%.1f", average))h."
    }

    private var anxietyPattern: String {
        guard !checkIns.isEmpty else { return "Ainda sem histórico suficiente." }
        let average = checkIns.prefix(14).map(\.anxiety).reduce(0, +) / Double(min(checkIns.count, 14))
        return "Média recente de \(String(format: "%.1f", average))/5."
    }

    private var triggerPattern: String {
        let triggers = checkIns.flatMap { triggerLabels(from: $0.journalEntry) }
        guard let mostCommon = Dictionary(grouping: triggers, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }) else {
            return "Nenhum gatilho recorrente ainda."
        }
        return "\(mostCommon.key) aparece com mais frequência."
    }

    private var medicationPattern: String {
        if medicationPlans.contains(where: { !$0.changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Há mudança cadastrada para acompanhar resposta."
        }
        let adherence = checkIns.isEmpty ? 0 : Double(checkIns.filter { $0.medicationTaken }.count) / Double(checkIns.count)
        return checkIns.isEmpty ? "Ainda sem adesão longitudinal." : "\(Int((adherence * 100).rounded()))% de adesão nos registros."
    }

    private var ppgPattern: String {
        guard ppgQuality > 0 else {
            return "Sem leitura PPG suficiente ainda."
        }
        if ppgQuality < 0.45 {
            return "Sinal fraco; repetir com dedo parado e flash coberto."
        }
        return "Ativação estimada \(Int((ppgStress * 100).rounded()))%, com qualidade \(Int((ppgQuality * 100).rounded()))%."
    }

    private var voicePattern: String {
        guard voicePauseRatio > 0 else {
            return "Sem amostra de voz ainda."
        }
        return "Pausas em \(Int((voicePauseRatio * 100).rounded()))% da amostra, sem salvar conteúdo."
    }

    private var typingPattern: String {
        guard typingSpeed > 0 else {
            return "Digite no diário para criar padrão."
        }
        return "\(Int(typingSpeed.rounded())) caracteres/min no app."
    }

    private var healthPattern: String {
        var parts: [String] = []
        if healthSleepHours > 0 {
            parts.append("sono \(String(format: "%.1f", healthSleepHours))h")
        }
        if healthSteps > 0 {
            parts.append("\(healthSteps) passos")
        }
        if healthHeartRate > 0 {
            parts.append("FC \(Int(healthHeartRate.rounded())) bpm")
        }
        return parts.isEmpty ? "Apple Health ainda sem dados sincronizados." : parts.joined(separator: " • ")
    }

    private func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }
}

private struct MiniTrendCard: View {
    let title: String
    let icon: String
    let values: [Double]
    let color: Color
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.75))
                        .frame(height: max(10, CGFloat(min(value / maxValue, 1)) * 54))
                }
            }
            .frame(height: 58, alignment: .bottom)

            Text(values.count == 1 ? "Hoje" : "Últimos \(values.count) registros")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OfflineSyncStatusCard: View {
    let pendingCount: Int
    let lastStatus: String
    let retrySync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Sprint 22: ícone reflete o estado real. Sincronizado = nuvem
            // com check verde. Pendente = nuvem cortada laranja (cloud.slash)
            // — semânticamente "fora do alcance da nuvem agora".
            Image(systemName: pendingCount == 0 ? "checkmark.icloud.fill" : "icloud.slash.fill")
                .font(.headline)
                .foregroundStyle(pendingCount == 0 ? .green : Color.neuroOrange)
                .frame(width: 36, height: 36)
                .background((pendingCount == 0 ? Color.green : Color.neuroYellow).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(pendingCount == 0 ? "Dados protegidos" : "Aguardando sincronização")
                    .font(.subheadline.weight(.bold))
                Text(lastStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if pendingCount > 0 {
                Button(action: retrySync) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Tentar sincronizar novamente")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BodySignalsIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.title2)
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Check-in fisiológico")
                        .font(.headline)
                    Text("Área experimental para sinais associados ao estado autonômico, como pulso, HRV estimada, respiração indireta e perfusão.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Não mede humor diretamente e não substitui avaliação clínica. Estes dados ficam fora das escalas PHQ-9, GAD-7, YMRS e do cálculo de risco.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct BodySignalsReadingCard: View {
    let heartRate: Double
    let hrv: Double
    let respiration: Double
    let perfusion: Double
    let stress: Double
    let quality: Double
    let status: String
    let isMeasuring: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "sensor.tag.radiowaves.forward", title: "PPG pela câmera")

            VStack(alignment: .leading, spacing: 8) {
                Text("Cubra a câmera traseira e o flash com o dedo, mantenha parado por 30 segundos e evite frio, cafeína, exercício recente e pressão excessiva.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: start) {
                        Label(isMeasuring ? "Medindo..." : "Medir com câmera e flash", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMeasuring)

                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isMeasuring)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Pulso", value: heartRate > 0 ? "\(Int(heartRate)) bpm" : "-", icon: "heart.fill", color: .red)
                BodySignalMetricPill(title: "HRV estimada", value: hrv > 0 ? "\(Int(hrv)) ms" : "-", icon: "point.3.connected.trianglepath.dotted", color: .teal)
                BodySignalMetricPill(title: "Respiração", value: respiration > 0 ? "\(Int(respiration))/min" : "-", icon: "lungs.fill", color: .indigo)
                BodySignalMetricPill(title: "Perfusão", value: perfusion > 0 ? String(format: "%.1f%%", perfusion) : "-", icon: "drop.fill", color: .blue)
                BodySignalMetricPill(title: "Estresse", value: stress > 0 ? "\(Int(stress))/100" : "-", icon: "bolt.heart.fill", color: .orange)
                BodySignalMetricPill(title: "Qualidade", value: quality > 0 ? "\(Int(quality * 100))%" : "-", icon: "checkmark.seal.fill", color: quality >= 0.45 ? .green : .orange)
            }

            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct BodySignalMetricPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BodySignalsBehaviorCard: View {
    let typingLatency: Double
    let typingSpeed: Double
    let interactionCount: Int
    let sessionMinutes: Double
    let voiceAverage: Double
    let voicePauseRatio: Double
    let voiceVariability: Double
    let voicePitch: Double
    let voicePitchVariability: Double
    let voiceSyllableEnergy: Double
    let voiceRhythm: Double
    let voiceStatus: String
    let isRecording: Bool
    let startVoice: () -> Void
    let stopVoice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "keyboard", title: "Digitação e voz")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Latência", value: typingLatency > 0 ? "\(Int(typingLatency))s" : "-", icon: "timer", color: .purple)
                BodySignalMetricPill(title: "Velocidade", value: typingSpeed > 0 ? "\(Int(typingSpeed)) c/min" : "-", icon: "keyboard.fill", color: .teal)
                BodySignalMetricPill(title: "Interações", value: "\(interactionCount)", icon: "hand.tap.fill", color: .blue)
                BodySignalMetricPill(title: "Sessão", value: String(format: "%.1f min", sessionMinutes), icon: "iphone", color: .indigo)
                BodySignalMetricPill(title: "Voz", value: voiceAverage > 0 ? "\(Int(voiceAverage * 100))%" : "-", icon: "waveform", color: .orange)
                BodySignalMetricPill(title: "Pausas", value: voicePauseRatio > 0 ? "\(Int(voicePauseRatio * 100))%" : "-", icon: "pause.circle.fill", color: .gray)
                BodySignalMetricPill(title: "Pitch", value: voicePitch > 0 ? "\(Int(voicePitch)) Hz" : "-", icon: "music.quarternote.3", color: .purple)
                BodySignalMetricPill(title: "Variação vocal", value: voicePitchVariability > 0 ? "\(Int(voicePitchVariability)) Hz" : "-", icon: "waveform.path", color: .pink)
                BodySignalMetricPill(title: "Energia fala", value: voiceSyllableEnergy > 0 ? "\(Int(voiceSyllableEnergy * 100))%" : "-", icon: "speaker.wave.2.fill", color: .teal)
                BodySignalMetricPill(title: "Ritmo", value: voiceRhythm > 0 ? "\(Int(voiceRhythm))/min" : "-", icon: "metronome.fill", color: .blue)
            }

            HStack(spacing: 10) {
                Button(action: startVoice) {
                    Label(isRecording ? "Gravando..." : "Medir voz", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecording)

                Button(action: stopVoice) {
                    Image(systemName: "stop.fill")
                        .frame(width: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!isRecording)
            }

            Text("Variação vocal: \(voiceVariability > 0 ? "\(Int(voiceVariability * 100))%" : "-"). \(voiceStatus)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct CombinedBodySignalCard: View {
    let ppgStress: Double
    let signalQuality: Double
    let typingSpeed: Double
    let voicePauseRatio: Double
    let voiceVariability: Double
    let sleepHours: Double
    let steps: Int

    private var combinedIndex: Double {
        let sleepLoad = sleepHours > 0 ? max(0, 7 - sleepHours) * 10 : 12
        let inactivityLoad = steps > 0 ? max(0, 5000 - Double(steps)) / 100 : 10
        let typingLoad = typingSpeed > 0 ? min(max(220 - typingSpeed, 0) / 4, 25) : 8
        let voiceLoad = voicePauseRatio * 16 + voiceVariability * 12
        let qualityPenalty = signalQuality > 0 ? (1 - signalQuality) * 18 : 10
        let evidenceWeight = signalQuality >= 0.45 ? 1.0 : 0.55
        return min(max((ppgStress * 0.40 + sleepLoad + inactivityLoad + typingLoad + voiceLoad) * evidenceWeight + qualityPenalty, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "point.3.connected.trianglepath.dotted", title: "Modelo combinado experimental")

            HStack(spacing: 12) {
                Text("\(Int(combinedIndex))")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 82, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.headline)
                    Text("Combina PPG, sono, passos, digitação e voz. Modelo heurístico não validado; não entra no risco clínico nem nas escalas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .panelStyle()
    }

    private var label: String {
        switch combinedIndex {
        case ..<35:
            "Baixa ativação autonômica"
        case ..<65:
            "Ativação intermediária"
        default:
            "Ativação elevada"
        }
    }

    private var color: Color {
        switch combinedIndex {
        case ..<35:
            .green
        case ..<65:
            .orange
        default:
            .red
        }
    }
}

private struct BodySignalsSourcesCard: View {
    let sleepHours: Double
    let steps: Int
    let heartRate: Double
    let activeEnergy: Double
    let syncHealth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "heart.text.square", title: "Fontes combinadas")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Sono Health", value: sleepHours > 0 ? String(format: "%.1fh", sleepHours) : "-", icon: "moon.zzz.fill", color: .indigo)
                BodySignalMetricPill(title: "Passos", value: steps > 0 ? "\(steps)" : "-", icon: "figure.walk", color: .teal)
                BodySignalMetricPill(title: "FC Health", value: heartRate > 0 ? "\(Int(heartRate)) bpm" : "-", icon: "heart.circle.fill", color: .red)
                BodySignalMetricPill(title: "Energia", value: activeEnergy > 0 ? "\(Int(activeEnergy)) kcal" : "-", icon: "flame.fill", color: .orange)
            }

            Button(action: syncHealth) {
                Label("Sincronizar Apple Health", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
    }
}

private struct BodySignalsLimitationsCard: View {
    private let limitations = [
        "PPG por câmera sofre interferência de movimento, temperatura, iluminação e posição do dedo.",
        "Cafeína, exercício, medicamentos e sono alteram pulso/HRV sem significar mudança de humor.",
        "Tristeza, fadiga e ansiedade podem produzir sinais fisiológicos parecidos.",
        "Para uso clínico, esses sinais precisam ser combinados com autorrelato, sono, atividade e escalas validadas."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "exclamationmark.triangle", title: "Limitações")

            ForEach(limitations, id: \.self) { item in
                Label(item, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }
}

private struct MonthlyMoodCalendarCard: View {
    let checkIns: [DailyCheckIn]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["D", "S", "T", "Q", "Q", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(icon: "calendar", title: "Cronograma mensal")
                Spacer()
                Text(monthTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(calendarDays) { day in
                    CalendarDayCell(day: day, checkIn: checkInByDay[day.dateKey])
                }
            }

            HStack(spacing: 8) {
                CalendarLegendDot(color: .red, text: "difícil")
                CalendarLegendDot(color: .orange, text: "oscilou")
                CalendarLegendDot(color: .neuroYellow, text: "neutro")
                CalendarLegendDot(color: .green, text: "bem")
            }
        }
        .panelStyle()
    }

    private var monthTitle: String {
        Date.now.formatted(.dateTime.month(.wide).year())
    }

    private var checkInByDay: [String: DailyCheckIn] {
        Dictionary(grouping: checkIns) { dateKey(for: $0.date) }
            .compactMapValues { entries in
                entries.max { $0.date < $1.date }
            }
    }

    private var calendarDays: [CalendarDay] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: .now),
            let dayRange = calendar.range(of: .day, in: .month, for: .now)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        var days: [CalendarDay] = (1..<firstWeekday).map { _ in CalendarDay(date: nil) }

        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                days.append(CalendarDay(date: date))
            }
        }

        return days
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date?

    var dateKey: String {
        guard let date else { return id.uuidString }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct CalendarDayCell: View {
    let day: CalendarDay
    let checkIn: DailyCheckIn?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                }

            if let date = day.date {
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.caption.weight(.bold))
                    if checkIn != nil {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                    }
                }
                .foregroundStyle(textColor)
            }
        }
        .frame(height: 42)
    }

    private var backgroundColor: Color {
        guard let checkIn else {
            return day.date == nil ? .clear : Color(.secondarySystemGroupedBackground)
        }

        switch checkIn.mood {
        case ...1.5:
            return .red.opacity(0.26)
        case ..<3:
            return .orange.opacity(0.26)
        case ..<4:
            return .neuroYellow.opacity(0.38)
        default:
            return .green.opacity(0.28)
        }
    }

    private var borderColor: Color {
        checkIn == nil ? Color(.separator).opacity(day.date == nil ? 0 : 0.22) : moodColor.opacity(0.65)
    }

    private var moodColor: Color {
        guard let checkIn else { return .secondary }
        switch checkIn.mood {
        case ...1.5:
            return .red
        case ..<3:
            return .orange
        case ..<4:
            return .neuroYellow
        default:
            return .green
        }
    }

    private var textColor: Color {
        checkIn == nil ? .secondary : moodColor
    }
}

private struct CalendarLegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct YearMoodOverviewCard: View {
    let checkIns: [DailyCheckIn]

    private let calendar = Calendar.current
    private let months = Calendar.current.shortMonthSymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "calendar.badge.clock", title: "Visão anual")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                    let average = averageMood(forMonth: index + 1)
                    VStack(spacing: 6) {
                        Text(month.capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color(for: average).opacity(average == nil ? 0.08 : 0.34))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(color(for: average).opacity(average == nil ? 0.12 : 0.55), lineWidth: 1)
                            }
                            .frame(height: 38)
                            .overlay {
                                Text(average.map { String(format: "%.1f", $0) } ?? "-")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(average == nil ? .secondary : color(for: average))
                            }
                    }
                }
            }

            Text("Cada mês mostra a média de humor salva nos registros diários.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func averageMood(forMonth month: Int) -> Double? {
        let year = calendar.component(.year, from: .now)
        let entries = checkIns.filter {
            calendar.component(.year, from: $0.date) == year &&
            calendar.component(.month, from: $0.date) == month
        }
        guard !entries.isEmpty else { return nil }
        return entries.map(\.mood).reduce(0, +) / Double(entries.count)
    }

    private func color(for value: Double?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case ...1.5:
            return .red
        case ..<3:
            return .orange
        case ..<4:
            return .neuroGold
        default:
            return .green
        }
    }
}

private struct MedicationPlanCard: View {
    @Binding var medicationName: String
    @Binding var medicationDose: String
    @Binding var medicationSchedule: String
    @Binding var medicationPrescription: String
    @Binding var medicationChangeNote: String
    let medicationPlans: [MedicationPlanEntry]
    let addMedication: () -> Void
    let removeMedication: (MedicationPlanEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "pills.fill", title: "Medicamentos")

            VStack(spacing: 10) {
                TextField("Nome do medicamento", text: $medicationName)
                TextField("Dose. Ex.: 50 mg", text: $medicationDose)
                TextField("Horário. Ex.: manhã e noite", text: $medicationSchedule)
                TextField("Prescrição/orientação. Ex.: após jantar", text: $medicationPrescription)
                TextField("Mudança recente de dose ou troca", text: $medicationChangeNote)
            }
            .textFieldStyle(.roundedBorder)

            Button(action: addMedication) {
                Label("Adicionar medicamento", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if medicationPlans.isEmpty {
                Text("Cadastre medicamentos, doses, horários, prescrição e mudanças para acompanhar resposta e efeitos colaterais ao longo do tempo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(medicationPlans) { medication in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "pills.circle.fill")
                                .foregroundStyle(Color.neuroOrange)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(medication.name)
                                    .font(.subheadline.weight(.bold))
                                Text([medication.dose, medication.schedule].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if !medication.prescription.isEmpty {
                                    Text(medication.prescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !medication.changeNote.isEmpty {
                                    Label(medication.changeNote, systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }

                            Spacer()

                            Button {
                                removeMedication(medication)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.neuroYellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CustomSymptomCard: View {
    @Binding var symptomName: String
    @Binding var symptomValue: Double
    let symptoms: [CustomSymptomEntry]
    let addSymptom: () -> Void
    let removeSymptom: (CustomSymptomEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "slider.horizontal.3", title: "Sintomas personalizados")

            TextField("Ex.: impulsividade, compulsão, dor, choro", text: $symptomName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(symptomName.isEmpty ? "Intensidade" : symptomName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(symptomValue))/5")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.neuroOrange)
                }

                Slider(value: $symptomValue, in: 1...5, step: 1)
                    .tint(.neuroGold)
            }

            Button(action: addSymptom) {
                Label("Adicionar sintoma", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(symptomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !symptoms.isEmpty {
                VStack(spacing: 8) {
                    ForEach(symptoms) { symptom in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(symptom.name)
                                    .font(.subheadline.weight(.bold))
                                ProgressView(value: symptom.value, total: 5)
                                    .tint(.neuroGold)
                            }

                            Text("\(Int(symptom.value))/5")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.neuroOrange)

                            Button {
                                removeSymptom(symptom)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SafetyPlanEditorCard: View {
    @Binding var safetyContact: String
    @Binding var warningSigns: String
    @Binding var strategies: String
    let signature: NeuroFlowRiskSignature
    let careFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "lifepreserver", title: "Plano de segurança")

            if signature.level != .low {
                VStack(alignment: .leading, spacing: 8) {
                    Label(signature.level == .high ? "Ação prioritária hoje" : "Atenção nas próximas 24-72h", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(alertColor)

                    ForEach(personalizedActions, id: \.self) { action in
                        Label(action, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(alertColor.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(alertColor.opacity(0.25), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Label(careFocus.safetyGuidance, systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField("Contato de confiança ou emergência", text: $safetyContact)
                .textFieldStyle(.roundedBorder)
            TextField("Meus sinais de alerta", text: $warningSigns)
                .textFieldStyle(.roundedBorder)
            TextField("O que costuma me ajudar", text: $strategies)
                .textFieldStyle(.roundedBorder)

            Text("Em risco imediato, procure emergência local ou contato de crise. Este plano não substitui atendimento profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var alertColor: Color {
        signature.level == .high ? .red : .orange
    }

    private var personalizedActions: [String] {
        var actions: [String] = []
        if !safetyContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append("Avisar ou combinar checagem com: \(safetyContact).")
        } else {
            actions.append("Definir um contato de confiança antes de uma crise.")
        }

        if signature.factors.contains(where: { $0.localizedCaseInsensitiveContains("sono") }) {
            actions.append("Priorizar rotina de sono e reduzir estímulos hoje.")
        }
        if signature.factors.contains(where: { $0.localizedCaseInsensitiveContains("medicação") || $0.localizedCaseInsensitiveContains("adesão") }) {
            actions.append("Conferir medicação, efeitos colaterais e combinar conduta com profissional.")
        }
        if signature.factors.contains(where: { $0.localizedCaseInsensitiveContains("gatilho") }) {
            actions.append("Evitar gatilhos identificados e usar estratégia de regulação.")
        }
        if !signature.focusAlerts.isEmpty {
            actions.append(careFocus.safetyGuidance)
        }
        if signature.level == .high {
            actions.append("Se houver risco imediato de se machucar, procurar emergência local agora.")
        }
        return Array(actions.prefix(5))
    }
}

private struct PsychoeducationCard: View {
    private let topics = [
        PsychoeducationTopic(
            icon: "moon.zzz.fill",
            title: "Sono e rotina",
            text: "Mudanças no sono podem aparecer antes de oscilações importantes. Observe horário de dormir, despertares e energia no dia seguinte.",
            color: Color.indigo
        ),
        PsychoeducationTopic(
            icon: "pills.fill",
            title: "Medicação",
            text: "Registrar tomada parcial, esquecimentos e efeitos colaterais ajuda a conversar com o profissional sem depender só da memória.",
            color: Color.teal
        ),
        PsychoeducationTopic(
            icon: "bolt.heart.fill",
            title: "Gatilhos",
            text: "Álcool, privação de sono, estresse e conflitos podem afetar sintomas. Com histórico, o app começa a mostrar padrões pessoais.",
            color: Color.orange
        ),
        PsychoeducationTopic(
            icon: "lifepreserver.fill",
            title: "Sinais de alerta",
            text: "Se houver risco de se machucar, procure ajuda imediata. O plano de segurança serve para lembrar contatos e estratégias já combinadas.",
            color: Color.red
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "book.pages", title: "Aprender sobre meu cuidado")

            Text("Informações curtas para entender melhor os registros e preparar conversas com seu profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(topics) { topic in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: topic.icon)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(topic.color)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.subheadline.weight(.bold))
                            Text(topic.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(topic.color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }
}

private struct PsychoeducationTopic: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let text: String
    let color: Color
}

private struct DSM5CriteriaGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

private struct DSM5FoundationCard: View {
    let selectedFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "brain.head.profile", title: "Por que pergunto isso?")

            Text("Triagem estruturada baseada em domínios clínicos do DSM-5/DSM-5-TR. O app organiza sinais para acompanhamento e conversa clínica, sem fechar diagnóstico automaticamente.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Label(selectedFocus.rawValue, systemImage: selectedFocus.icon)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(selectedFocus.dsm5MonitoringFrame)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(selectedFocus.dsm5SignalSummary, id: \.self) { signal in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Color.neuroOrange)
                            Text(signal)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.neuroYellow.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(selectedFocus.dsm5CriteriaGroups) { group in
                        DSM5CriteriaGroupView(group: group)
                    }
                }

                Label("Para uso clínico: confirmar duração, intensidade, prejuízo funcional, curso longitudinal, risco atual, diagnósticos diferenciais e exclusões médicas/substâncias antes de qualquer conclusão.", systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .panelStyle()
    }
}

private struct DSM5CriteriaGroupView: View {
    let group: DSM5CriteriaGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            ForEach(group.items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "smallcircle.filled.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.neuroGold)
                        .padding(.top, 3)

                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MedicationTrackerCard: View {
    let medicationStatus: MedicationStatus
    let adherence: Double
    let sideEffects: String
    let checkIns: [DailyCheckIn]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "pills", title: "Medicação")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                MoodSignalPill(
                    title: "Hoje",
                    value: medicationStatus.rawValue,
                    icon: medicationStatus == .taken ? "checkmark.seal" : "bell.badge",
                    color: medicationStatus.color
                )

                MoodSignalPill(
                    title: "Adesão recente",
                    value: "\(String(format: "%.0f", adherence * 100))%",
                    icon: "chart.pie",
                    color: adherence >= 0.8 ? .green : .orange
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                MoodSignalPill(
                    title: "Com medicação",
                    value: display(averageMood(medicationTaken: true)),
                    icon: "face.smiling",
                    color: .green
                )

                MoodSignalPill(
                    title: "Sem medicação",
                    value: display(averageMood(medicationTaken: false)),
                    icon: "chart.line.downtrend.xyaxis",
                    color: .orange
                )
            }

            Text(sideEffects.isEmpty ? "Registre efeitos colaterais para comparar medicação e sintomas ao longo do tempo." : "Efeito anotado hoje: \(sideEffects)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(abandonmentInsight)
                .font(.caption.weight(.semibold))
                .foregroundStyle(adherence < 0.7 ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var abandonmentInsight: String {
        if checkIns.count < 3 {
            return "Com mais registros, o app compara adesão, efeitos colaterais e sintomas percebidos."
        }

        if adherence < 0.7 {
            return "Adesão baixa recentemente. Vale revisar esquecimento, efeitos colaterais ou dificuldade de rotina."
        }

        return "Adesão estável. Continue registrando para observar curva de resposta percebida."
    }

    private func averageMood(medicationTaken: Bool) -> Double? {
        let filtered = checkIns.filter { $0.medicationTaken == medicationTaken }
        guard !filtered.isEmpty else { return nil }
        return filtered.map(\.mood).reduce(0, +) / Double(filtered.count)
    }

    private func display(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(String(format: "%.1f", value))/5"
    }
}

private struct CircadianStabilityCard: View {
    let sleepHours: Double
    let averageSleep: Double
    let checkInCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "moon.stars", title: "Ritmo de sono")

            HStack(spacing: 10) {
                MoodSignalPill(title: "Hoje", value: "\(String(format: "%.1f", sleepHours))h", icon: "bed.double", color: sleepColor)
                MoodSignalPill(title: "Índice circadiano", value: stabilityLabel, icon: "clock", color: stabilityColor)
            }

            MoodSignalPill(
                title: "Desorganização do sono",
                value: "\(disorganizationScore)/100",
                icon: "waveform.path",
                color: disorganizationScore >= 60 ? .red : disorganizationScore >= 35 ? .orange : .green
            )

            Text("Sono irregular pode preceder piora de humor, ansiedade ou energia. Com mais registros, este índice fica mais útil.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var stabilityLabel: String {
        guard checkInCount > 1 else { return "Inicial" }
        return abs(sleepHours - averageSleep) <= 1.5 ? "Estável" : "Oscilando"
    }

    private var stabilityColor: Color {
        stabilityLabel == "Oscilando" ? .orange : .green
    }

    private var sleepColor: Color {
        sleepHours < 5.5 ? .red : sleepHours < 7 ? .orange : .indigo
    }

    private var disorganizationScore: Int {
        guard checkInCount > 1 else { return 0 }
        let deviation = min(abs(sleepHours - averageSleep), 5)
        return Int((deviation / 5) * 100)
    }
}

private struct TriggerMapCard: View {
    @Binding var alcoholTrigger: Bool
    @Binding var poorSleepTrigger: Bool
    @Binding var stressTrigger: Bool
    @Binding var conflictTrigger: Bool
    @Binding var routineChangeTrigger: Bool
    @Binding var menstrualTrigger: Bool
    @Binding var customTriggerText: String
    @Binding var customTriggers: [String]
    let checkIns: [DailyCheckIn]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bolt.badge.clock", title: "Gatilhos do dia")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                TriggerToggle(title: "Álcool", icon: "wineglass", color: .purple, isOn: $alcoholTrigger)
                TriggerToggle(title: "Pouco sono", icon: "moon.zzz", color: .indigo, isOn: $poorSleepTrigger)
                TriggerToggle(title: "Estresse", icon: "flame", color: .red, isOn: $stressTrigger)
                TriggerToggle(title: "Conflito", icon: "person.2.slash", color: .orange, isOn: $conflictTrigger)
                TriggerToggle(title: "Rotina mudou", icon: "arrow.triangle.2.circlepath", color: .teal, isOn: $routineChangeTrigger)
                TriggerToggle(title: "Ciclo menstrual", icon: "calendar.badge.clock", color: .pink, isOn: $menstrualTrigger)
            }

            HStack(spacing: 8) {
                TextField("Adicionar gatilho", text: $customTriggerText)
                    .textInputAutocapitalization(.sentences)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    addCustomTrigger()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(customTriggerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !customTriggers.isEmpty {
                FlowLayout(items: customTriggers)
            }

            Text(triggerInsight)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var triggerInsight: String {
        guard checkIns.count >= 3 else {
            return "Com alguns dias de histórico, o app começa a relacionar gatilhos com sono, ansiedade e humor."
        }

        let lastThree = Array(checkIns.prefix(3))
        let lowSleepCount = lastThree.filter { $0.sleepHours < 6 }.count
        let highAnxietyCount = lastThree.filter { $0.anxiety >= 4 }.count
        let lowMoodCount = lastThree.filter { $0.mood <= 2 }.count

        if lowSleepCount >= 2 && (highAnxietyCount >= 1 || lowMoodCount >= 1) {
            return "Insight: pouco sono apareceu junto de maior ansiedade ou queda de humor nos últimos registros."
        }

        if highAnxietyCount >= 2 {
            return "Insight: ansiedade alta apareceu repetidamente. Marcar gatilhos ajuda a encontrar padrões."
        }

        return "Nenhum padrão forte ainda. Continue marcando gatilhos para personalizar os alertas."
    }

    private func addCustomTrigger() {
        let trimmed = customTriggerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customTriggers.contains(trimmed) else {
            return
        }

        customTriggers.append(trimmed)
        customTriggerText = ""
    }
}

private struct TriggerToggle: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.52), color.opacity(0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 1.6)
            }
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .padding(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(isOn ? 1.02 : 1)
        }
        .buttonStyle(.plain)
    }
}

private struct EngagementCard: View {
    let checkInCount: Int
    let recentCheckIns: [DailyCheckIn]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "rosette", title: "Constância")

            HStack(spacing: 10) {
                MoodSignalPill(title: "Registros", value: "\(checkInCount)", icon: "calendar", color: .neuroYellow)
                MoodSignalPill(title: "Sequência", value: "\(streak) dias", icon: "flame", color: streak >= 7 ? .green : .orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                BadgePill(title: "Primeiro passo", isUnlocked: checkInCount >= 1)
                BadgePill(title: "7 dias", isUnlocked: streak >= 7)
                BadgePill(title: "14 registros", isUnlocked: checkInCount >= 14)
            }

            Text(streak >= 7 ? "Boa sequência. Acompanhar por vários dias melhora a percepção de padrões." : "Tente registrar um pouco por dia. Mesmo respostas rápidas já ajudam.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: min(Double(streak), 7), total: 7) {
                Text("Meta saudável: 7 dias de check-in")
                    .font(.caption.weight(.semibold))
            }
            .tint(.neuroYellow)
        }
        .panelStyle()
    }

    private var streak: Int {
        let days = Set(recentCheckIns.map { Calendar.current.startOfDay(for: $0.date) })
        var count = 0
        var day = Calendar.current.startOfDay(for: .now)

        while days.contains(day) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }

        return count
    }
}

private struct BadgePill: View {
    let title: String
    let isUnlocked: Bool

    var body: some View {
        Label(title, systemImage: isUnlocked ? "star.fill" : "star")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isUnlocked ? Color.neuroYellow.opacity(0.34) : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isUnlocked ? .orange : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CareFocusCard: View {
    @Binding var selectedFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.crop.circle.badge.checkmark", title: "Foco do acompanhamento")

            Picker("Foco do acompanhamento", selection: $selectedFocus) {
                ForEach(CareFocus.allCases) { focus in
                    Text(focus.rawValue).tag(focus)
                }
            }
            .pickerStyle(.menu)

            Text(selectedFocus.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(selectedFocus.modules, systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct ClinicalPersonalizationCard: View {
    let selectedFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "slider.horizontal.below.rectangle", title: "Personalização clínica")

            Text("O acompanhamento muda conforme o foco escolhido nas configurações e na evolução.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                PersonalizationTile(icon: "heart.text.square", title: "Escala principal", text: selectedFocus.preferredScale.rawValue, tint: .orange)
                PersonalizationTile(icon: "waveform.path.ecg", title: "Sinais priorizados", text: biomarkerText, tint: .indigo)
                PersonalizationTile(icon: "bell.badge", title: "Risco observado", text: riskText, tint: .red)
                PersonalizationTile(icon: "calendar.badge.clock", title: "Rotina de revisão", text: cadenceText, tint: .green)
            }
        }
        .panelStyle()
    }

    private var biomarkerText: String {
        switch selectedFocus {
        case .bipolar:
            "sono, energia, irritabilidade, PPG e adesão"
        case .depression:
            "humor, energia, sono, apetite e voz"
        case .anxiety:
            "ansiedade, sono, PPG, respiração e gatilhos"
        case .borderline:
            "intensidade emocional, conflitos e segurança"
        case .burnout:
            "energia, sono, atividade e recuperação"
        case .adhd:
            "rotina, sono, digitação e adesão"
        case .postpartum:
            "sono, humor, ansiedade e rede de apoio"
        }
    }

    private var riskText: String {
        switch selectedFocus {
        case .bipolar:
            "virada de humor, sono reduzido e impulsividade"
        case .depression:
            "queda de humor, desesperança e segurança"
        case .anxiety:
            "ansiedade persistente e hiperativação"
        case .borderline:
            "crise interpessoal e impulsividade"
        case .burnout:
            "exaustão sustentada e perda de rotina"
        case .adhd:
            "desorganização funcional e baixa adesão"
        case .postpartum:
            "privação de sono, humor e sinais de alerta"
        }
    }

    private var cadenceText: String {
        switch selectedFocus {
        case .bipolar, .borderline, .postpartum:
            "revisão mais próxima se sono ou segurança mudarem"
        case .depression, .anxiety:
            "revisão semanal quando sintomas subirem"
        case .burnout, .adhd:
            "revisão por padrão de rotina e funcionamento"
        }
    }
}

private struct PersonalizationTile: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PatientReportExportCard: View {
    let reportPreview: String
    let pdfURL: URL?
    let csvURL: URL?
    let generateReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "square.and.arrow.up", title: "Relatório para consulta")

            Text("Gere um resumo com evolução, check-ups e sinais recentes para compartilhar com seu profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: generateReport) {
                Label("Gerar resumo", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if !reportPreview.isEmpty {
                Text(reportPreview)
                    .font(.caption.monospaced())
                    .lineLimit(6)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Compartilhar PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Compartilhar CSV", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                ShareLink(item: reportPreview) {
                    Label("Compartilhar texto", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .panelStyle()
    }
}

private struct MonthlyReportAutomationCard: View {
    @Binding var isEnabled: Bool
    let reportStatusMessage: String
    let generateReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "calendar.badge.plus", title: "Relatório mensal")

            Toggle("Preparar relatório mensal automaticamente", isOn: $isEnabled)
                .toggleStyle(.switch)

            HStack(spacing: 10) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(isEnabled ? .green : .secondary)
                Text(isEnabled ? "O app já deixa o relatório mensal pronto quando houver dados suficientes." : "Ative para transformar o histórico do mês em resumo para consulta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: generateReport) {
                Label("Gerar relatório do mês agora", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // P1-2: reportStatusMessage migrado para toast central.
        }
        .panelStyle()
    }
}

private struct BackupExportCard: View {
    let backupURL: URL?
    @Binding var isAutomatic: Bool
    @Binding var intervalDays: Int
    let lastAutomaticBackupAt: Double
    let backupStatus: String
    let backgroundStatus: String
    let makeBackup: () -> Void
    let restoreBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "externaldrive.badge.checkmark", title: "Backup dos dados")

            Text("Gere, compartilhe ou restaure um arquivo JSON com registros, escalas, medicações, sintomas personalizados e plano de segurança.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Backup automático ao salvar diário", isOn: $isAutomatic)
                .toggleStyle(.switch)

            Stepper("Backup recorrente: a cada \(intervalDays) dia(s)", value: $intervalDays, in: 1...30)
                .disabled(!isAutomatic)

            Label(lastBackupText, systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Label(backgroundStatus, systemImage: "iphone.and.arrow.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: makeBackup) {
                Label("Gerar backup", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: restoreBackup) {
                Label("Restaurar backup", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Compartilhar backup", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !backupStatus.isEmpty {
                Text(backupStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var lastBackupText: String {
        guard lastAutomaticBackupAt > 0 else {
            return "Nenhum backup automático gerado ainda."
        }

        let date = Date(timeIntervalSince1970: lastAutomaticBackupAt)
        return "Último backup automático: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct CareTeamAutoSendCard: View {
    @Binding var isEnabled: Bool
    @Binding var contact: String
    @Binding var caregiverName: String
    @Binding var caregiverRelationship: String
    let canShare: Bool
    let canShareCaregiver: Bool
    let status: String
    let caregivers: [BackendCaregiverContact]
    let saveCaregiver: () -> Void
    let refreshCaregivers: () -> Void
    let sendNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "paperplane.fill", title: "Envio automático")

            Toggle("Enviar relatório ao médico/cuidador", isOn: $isEnabled)
                .toggleStyle(.switch)

            TextField("E-mail ou contato do médico/cuidador", text: $contact)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Nome do cuidador", text: $caregiverName)
                    .textFieldStyle(.roundedBorder)

                TextField("Vínculo", text: $caregiverRelationship)
                    .textFieldStyle(.roundedBorder)
            }

            Label(canShare ? "Compartilhamento autorizado" : "Ative consentimento e compartilhamento para enviar", systemImage: canShare ? "checkmark.seal.fill" : "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canShare ? .green : .secondary)

            HStack(spacing: 10) {
                Button(action: saveCaregiver) {
                    Label("Cadastrar cuidador", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canShareCaregiver || contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: refreshCaregivers) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Atualizar cuidadores")
            }

            if !caregivers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(caregivers) { caregiver in
                        HStack(spacing: 10) {
                            Image(systemName: caregiver.shareEnabled ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark")
                                .foregroundStyle(caregiver.shareEnabled ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(caregiver.name)
                                    .font(.subheadline.weight(.semibold))

                                Text(caregiverSubtitle(caregiver))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Button(action: sendNow) {
                Label("Enviar relatório agora", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled || !canShare)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private func caregiverSubtitle(_ caregiver: BackendCaregiverContact) -> String {
        let relationship = caregiver.relationship.isEmpty ? "cuidador" : caregiver.relationship
        let permission = caregiver.shareEnabled ? "autorizado" : "bloqueado"
        return "\(relationship) • \(caregiver.contact) • \(permission)"
    }
}

private struct HealthKitIntegrationCard: View {
    @Binding var isEnabled: Bool
    let status: String
    let sleepHours: Double
    let steps: Int
    let heartRate: Double
    let activeEnergy: Double
    let sync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "heart.text.square.fill", title: "Apple Health")

            Toggle("Usar dados do Apple Health", isOn: $isEnabled)
                .toggleStyle(.switch)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                HealthMetricPill(title: "Sono", value: String(format: "%.1fh", sleepHours), icon: "moon.zzz", color: .indigo)
                HealthMetricPill(title: "Passos", value: "\(steps)", icon: "figure.walk", color: .teal)
                HealthMetricPill(title: "FC média", value: heartRate > 0 ? String(format: "%.0f bpm", heartRate) : "-", icon: "heart.fill", color: .red)
                HealthMetricPill(title: "Energia", value: activeEnergy > 0 ? String(format: "%.0f kcal", activeEnergy) : "-", icon: "flame.fill", color: .orange)
            }

            Button(action: sync) {
                Label("Conectar e sincronizar Health", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct HealthMetricPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RemotePushCard: View {
    @Binding var isEnabled: Bool
    let status: String
    let token: String
    let register: () -> Void
    let uploadToken: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bell.and.waves.left.and.right.fill", title: "Push remoto")

            Toggle("Permitir alertas remotos", isOn: $isEnabled)
                .toggleStyle(.switch)

            Button(action: register) {
                Label("Registrar no APNs", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)

            Button(action: uploadToken) {
                Label("Enviar token ao backend", systemImage: "server.rack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(token.isEmpty)

            if !token.isEmpty {
                Text("Token recebido: \(String(token.prefix(12)))...")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct ProductionReadinessCard: View {
    private let rows = [
        ("heart.text.square", "Apple Health", "Exige ativar HealthKit no projeto e pedir permissão para sono, passos e frequência cardíaca."),
        ("bell.and.waves.left.and.right", "Push remoto", "Exige APNs/Firebase, backend publicado e vínculo real médico-paciente."),
        ("server.rack", "Deploy e PostgreSQL", "Exige servidor/cloud, domínio, HTTPS, DATABASE_URL, backups e monitoramento."),
        ("checkmark.seal", "Escalas e validação", "Exige licença/tradução oficial quando aplicável e validação clínica formal com profissionais.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "shippingbox.and.arrow.backward", title: "Produção")

            ForEach(rows, id: \.1) { row in
                ComplianceRow(icon: row.0, title: row.1, description: row.2)
            }
        }
        .panelStyle()
    }
}

private struct ClinicalValidationRoadmapCard: View {
    private let rows = [
        ("waveform.path.ecg", "Validar PPG", "Comparar câmera/flash com Apple Watch, oxímetro ou cinta cardíaca em amostras reais."),
        ("mic", "Validar voz e digitação", "Medir apenas metadados, sem conteúdo, e comparar com escalas e avaliação clínica."),
        ("exclamationmark.triangle", "Falsos alertas", "Registrar quantos alertas foram úteis, excessivos ou perdidos antes de uso clínico."),
        ("person.2.badge.gearshape", "Revisão profissional", "Psiquiatras/psicólogos precisam revisar regras, linguagem, crise e limites do app."),
        ("checkmark.seal", "Estudo de efetividade", "Provar melhora em monitoramento, adesão ou desfechos antes de chamar de produto clínico validado.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "checklist.checked", title: "Validação para inovação")

            Text("O app já prepara a coleta multimodal e os insights, mas a validação depende de estudo real com pessoas e profissionais.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(rows, id: \.1) { row in
                ComplianceRow(icon: row.0, title: row.1, description: row.2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Métricas do estudo piloto")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                    ValidationMetricPill(title: "Sensibilidade", detail: "crises detectadas")
                    ValidationMetricPill(title: "Especificidade", detail: "dias estáveis corretos")
                    ValidationMetricPill(title: "Falsos alertas", detail: "alertas sem crise")
                    ValidationMetricPill(title: "Antecedência", detail: "dias antes da piora")
                    ValidationMetricPill(title: "Adesão", detail: "uso diário")
                    ValidationMetricPill(title: "Utilidade clínica", detail: "médico/paciente")
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .panelStyle()
    }
}

private struct ValidationMetricPill: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AutomaticWellbeingCheckupCard: View {
    let results: [AutomaticScaleResult]
    let statusMessage: String
    let canSave: Bool
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-up do bem-estar")
                        .font(.headline)
                    // P2-8 (UX): subtitle reforça natureza estimada antes de
                    // o paciente ver as pontuações, prevenindo interpretação
                    // incorreta como resultado clínico válido.
                    Text("Estimativa baseada nos seus sliders — não substitui avaliação formal.")
                        .font(.subheadline)
                        .foregroundStyle(.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.scale.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text("\(result.score)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(color(for: result))

                        Text(result.interpretation)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: result))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color(for: result).opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color(for: result).opacity(0.25), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Text("Observação: esta é uma estimativa automática de apoio. Aplicação oficial/validada das escalas exige instrumento autorizado e contexto clínico adequado.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: save) {
                Label("Salvar check-up automático", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)

            if !statusMessage.isEmpty {
                Label(statusMessage, systemImage: statusMessage.contains("Não") ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusMessage.contains("Não") ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private func color(for result: AutomaticScaleResult) -> Color {
        switch result.scale {
        case .phq9:
            result.score >= 20 ? .red : result.score >= 10 ? .orange : .green
        case .gad7:
            result.score >= 15 ? .red : result.score >= 10 ? .orange : .green
        case .ymrs:
            result.score >= 22 ? .red : result.score >= 13 ? .orange : .green
        }
    }
}

private struct TodayMoodOverviewCard: View {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let medicationTaken: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Resumo de hoje", systemImage: "calendar.day.timeline.left")
                        .font(.headline)

                    Text(Date.now, format: .dateTime.day().month(.abbreviated))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: overviewIcon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(overviewColor)
                    .frame(width: 42, height: 42)
                    .background(overviewColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                MoodSignalPill(
                    title: "Humor",
                    value: moodLabel,
                    icon: "face.smiling",
                    color: moodColor
                )

                MoodSignalPill(
                    title: "Ansiedade",
                    value: anxietyLabel,
                    icon: "waveform.path.ecg",
                    color: anxietyColor
                )

                MoodSignalPill(
                    title: "Sono",
                    value: "\(String(format: "%.1f", sleepHours))h",
                    icon: "moon.zzz",
                    color: sleepColor
                )

                MoodSignalPill(
                    title: "Medicação",
                    value: medicationTaken ? "Tomada" : "Pendente",
                    icon: medicationTaken ? "checkmark.seal" : "exclamationmark.triangle",
                    color: medicationTaken ? .green : .orange
                )
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), overviewColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(overviewColor.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var moodLabel: String {
        if mood <= 1.5 {
            return "Baixo"
        }

        if mood >= 4 {
            return "Bem"
        }

        return "Ok"
    }

    private var anxietyLabel: String {
        if anxiety <= 1.5 {
            return "Leve"
        }

        if anxiety >= 4 {
            return "Alta"
        }

        return "Média"
    }

    private var overviewIcon: String {
        mood >= 4 && anxiety <= 2 ? "sun.max.fill" : "heart.text.square.fill"
    }

    private var overviewColor: Color {
        if anxiety >= 4 || mood <= 1.5 {
            return .red
        }

        if anxiety >= 3 || sleepHours < 6 {
            return .orange
        }

        return .neuroYellow
    }

    private var moodColor: Color {
        if mood <= 1.5 {
            return .red
        }

        if mood >= 4 {
            return .green
        }

        return .orange
    }

    private var anxietyColor: Color {
        if anxiety <= 1.5 {
            return .green
        }

        if anxiety >= 4 {
            return .red
        }

        return .orange
    }

    private var sleepColor: Color {
        if sleepHours < 5.5 {
            return .red
        }

        if sleepHours < 7 {
            return .orange
        }

        return .indigo
    }
}

private struct MoodSignalPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct DailySafetyChoices: View {
    @Binding var medicationStatus: MedicationStatus
    @Binding var safetyStatus: SafetyStatus

    var body: some View {
        VStack(spacing: 10) {
            MedicationStatusCard(status: $medicationStatus)
            SafetyStatusCard(status: $safetyStatus)
        }
    }
}

private struct MedicationStatusCard: View {
    @Binding var status: MedicationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(status.emoji)
                    .font(.system(size: 34))
                    .frame(width: 54, height: 54)
                    .background(status.color.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Medicação")
                        .font(.headline)

                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(MedicationStatus.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            status = option
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(option.emoji)
                                .font(.title3)
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(status == option ? option.color.opacity(0.20) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(status == option ? option.color : .secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(status == option ? option.color.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.color.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SafetyStatusCard: View {
    @Binding var status: SafetyStatus
    @State private var isConfirmingUrgent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(status.emoji)
                    .font(.system(size: 34))
                    .frame(width: 54, height: 54)
                    .background(status.color.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Segurança hoje")
                        .font(.headline)

                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(SafetyStatus.allCases) { option in
                    Button {
                        if option == .urgent && status != .urgent {
                            isConfirmingUrgent = true
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                status = option
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(option.emoji)
                                .font(.title3)
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(status == option ? option.color.opacity(0.20) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(status == option ? option.color : .secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(status == option ? option.color.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.color.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Confirmar sinal de risco?", isPresented: $isConfirmingUrgent) {
            Button("Marcar como urgente", role: .destructive) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    status = .urgent
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ao marcar como urgente, o app registra ideação suicida neste check-in e dispara alerta para a equipe de cuidado autorizada (médico vinculado e/ou cuidadores). Se houver risco imediato, ligue para 188 (CVV) ou 192 (SAMU) agora.")
        }
    }
}

// P2-7 (UX): adicionado parâmetro opcional `skipLabel` + `skipValue`.
// Quando presente, exibe um botão extra "Não se aplica" que seta o valor
// para `skipValue` (default 0). Usado em Libido para evitar que o campo
// obrigatório com valor default 3 produza ruído de dados em pacientes
// que simplesmente ignoram o campo.
private struct VisualMetricPicker: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let options: [MetricOption]
    var suffix = ""
    var skipLabel: String? = nil
    var skipValue: Double = 0.0

    var isSkipped: Bool { skipLabel != nil && abs(value - skipValue) < 0.1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(isSkipped ? "—" : displayValue)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], spacing: 6) {
                ForEach(options) { option in
                    Button {
                        value = option.value
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isSelected(option) ? option.color.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(isSelected(option) ? option.color : .secondary)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected(option) ? option.color : Color.clear, lineWidth: 1.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                if let label = skipLabel {
                    Button {
                        value = skipValue
                    } label: {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isSkipped ? Color.secondary.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(isSkipped ? .primary : .secondary)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSkipped ? Color.secondary.opacity(0.4) : Color.clear, lineWidth: 1.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func isSelected(_ option: MetricOption) -> Bool {
        !isSkipped && abs(value - option.value) < 0.1
    }

    private var displayValue: String {
        if suffix == "h" {
            return "\(String(format: "%.1f", value))h"
        }

        return "\(Int(value))/5"
    }
}

private struct LabeledTextEditor: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            TextEditor(text: $text)
                .frame(minHeight: 88)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

private struct PatientFeedbackCard: View {
    let summary: LongitudinalSummary
    let canSave: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(color)

            Text(canSave ? patientText : "Ative o consentimento nas configurações para salvar seus registros com segurança.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [color.opacity(0.14), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch summary.riskLevel {
        case .low:
            "Seu dia parece estável"
        case .moderate:
            "Vale acompanhar de perto"
        case .high:
            "Você merece apoio agora"
        }
    }

    private var color: Color {
        switch summary.riskLevel {
        case .low:
            .neuroYellow
        case .moderate:
            .orange
        case .high:
            .red
        }
    }

    private var patientText: String {
        switch summary.riskLevel {
        case .low:
            "Continue registrando aos poucos. Pequenos registros ajudam a enxergar padrões sem precisar lembrar tudo depois."
        case .moderate:
            "Sono, ansiedade ou humor podem estar oscilando. Se isso continuar, compartilhe com seu profissional de confiança."
        case .high:
            "Se estiver em risco ou sem segurança, procure ajuda imediatamente. O app apoia o cuidado, mas não substitui atendimento."
        }
    }
}

private struct ScaleAccessCard: View {
    @Binding var isShowingScales: Bool
    let cadence: String
    let recentAssessmentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.neuroYellow, .neuroGold, .neuroOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-up do bem-estar")
                        .font(.headline)

                    Text("Algumas perguntas rápidas ajudam a acompanhar padrões ao longo do tempo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Label("\(recentAssessmentCount) check-ups", systemImage: "chart.bar.doc.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation {
                        isShowingScales.toggle()
                    }
                } label: {
                    Label(isShowingScales ? "Ocultar" : "Abrir", systemImage: isShowingScales ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.bordered)
            }
        }
        .panelStyle()
    }
}

private struct CrisisSupportCard: View {
    let safetyContact: String
    let warningSigns: String
    let strategies: String

    private var trustedNumberDigits: String {
        safetyContact.filter { $0.isNumber }
    }

    private var trustedTelURL: URL? {
        let digits = trustedNumberDigits
        guard digits.count >= 8 else { return nil }
        return URL(string: "tel://\(digits)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plano de segurança", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("Você marcou um sinal de risco. Este app não substitui atendimento de emergência. Procure uma pessoa de confiança, seu médico assistente ou um serviço de urgência agora se houver risco imediato.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                if let url = URL(string: "tel://188") {
                    crisisCallButton(
                        url: url,
                        title: "Ligar para CVV (188)",
                        subtitle: "Centro de Valorização da Vida — 24h, gratuito.",
                        tint: .red
                    )
                }

                if let url = URL(string: "tel://192") {
                    crisisCallButton(
                        url: url,
                        title: "SAMU (192)",
                        subtitle: "Emergência médica — risco imediato à vida.",
                        tint: .red
                    )
                }

                if let url = trustedTelURL {
                    crisisCallButton(
                        url: url,
                        title: "Ligar para meu contato de segurança",
                        subtitle: safetyContact,
                        tint: .orange
                    )
                }
            }

            if !warningSigns.isEmpty {
                planSection(title: "Meus sinais de alerta", body: warningSigns)
            }

            if !strategies.isEmpty {
                planSection(title: "Minhas estratégias", body: strategies)
            }

            VStack(alignment: .leading, spacing: 8) {
                ClinicalSignal(icon: "person.2.fill", title: "Rede de apoio", description: "Avise alguém de confiança e evite ficar sozinho durante a crise.")
                ClinicalSignal(icon: "pills.fill", title: "Meios de risco", description: "Afaste medicamentos, objetos cortantes ou outros meios de autolesão.")
            }

            Text("Para produção, este fluxo deve ser revisado por equipe clínica e adaptado ao país/região de uso.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func crisisCallButton(url: URL, title: String, subtitle: String, tint: Color) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityHint("Abre o discador com este número")
    }

    private func planSection(title: String, body content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ScaleQuestionRow: View {
    let number: Int
    let question: String
    let range: ClosedRange<Int>
    @Binding var answer: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(question)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Picker("Resposta", selection: $answer) {
                ForEach(Array(range), id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}

private struct ScaleResultCard: View {
    let scale: ScaleKind
    let score: Int
    let interpretation: String
    let hasCriticalPHQ9Answer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Resultado de agora", systemImage: "sparkline")
                    .font(.headline)

                Spacer()

                Text("\(score) pontos")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.orange)
            }

            Text(interpretation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(resultColor)

            Text(scoreRangeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasCriticalPHQ9Answer {
                Label("Item 9 positivo: requer revisão clínica prioritária.", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultColor: Color {
        switch scale {
        case .phq9:
            score >= 20 ? .red : score >= 10 ? .orange : .green
        case .gad7:
            score >= 15 ? .red : score >= 10 ? .orange : .green
        case .ymrs:
            score >= 22 ? .red : score >= 13 ? .orange : .green
        }
    }

    private var scoreRangeDescription: String {
        switch scale {
        case .phq9:
            "PHQ-9: 0-4 mínimo, 5-9 leve, 10-14 moderado, 15-19 moderadamente grave, 20-27 grave."
        case .gad7:
            "GAD-7: 0-4 mínimo, 5-9 leve, 10-14 moderado, 15-21 grave."
        case .ymrs:
            "YMRS: 11 itens, total 0-60. Faixas operacionais no app: 0-12 mínimo/ausente, 13-21 leve a moderado, 22+ marcado a grave."
        }
    }
}

private struct RiskSummaryCard: View {
    let summary: LongitudinalSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Classificação longitudinal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(summary.riskLevel.rawValue)
                        .font(.title.weight(.bold))
                }

                Spacer()

                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(color)
            }

            HStack(spacing: 10) {
                StatBadge(title: "Sono médio", value: "\(String(format: "%.1f", summary.averageSleep))h", icon: "moon.zzz")
                StatBadge(title: "Adesão", value: "\(String(format: "%.0f", summary.medicationAdherence * 100))%", icon: "pills")
            }

            Text("IA e regras clínicas são usadas exclusivamente como apoio à decisão. Diagnóstico e conduta permanecem responsabilidade do profissional de saúde.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var color: Color {
        switch summary.riskLevel {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

private struct TextRiskCard: View {
    let title: String
    let assessment: TextRiskAssessment
    var patientStyle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: patientStyle ? "text.bubble" : "text.magnifyingglass")
                    .font(.headline)

                Spacer()

                Text(patientStyle ? friendlyLevel : assessment.level.rawValue)
                    .font(.headline)
                    .foregroundStyle(color)
            }

            Text(assessment.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !assessment.detectedTerms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(patientStyle ? "Pontos de atenção" : "Termos detectados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(items: assessment.detectedTerms)
                }
            }

            Text(assessment.recommendation)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)

            Text(patientStyle ? "Esse retorno é só um apoio. Em situação urgente, procure ajuda imediatamente." : "Classificação automatizada de apoio; não substitui avaliação clínica.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var friendlyLevel: String {
        switch assessment.level {
        case .low:
            "Tranquilo"
        case .moderate:
            "Atenção"
        case .high:
            "Prioritário"
        }
    }

    private var color: Color {
        switch assessment.level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

private struct AccessGateCard: View {
    let activeRole: AccessRole
    let hasSharingConsent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Acesso médico bloqueado", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Sprint A: a "aba Segurança" não existe — desde Sprint 19 as tabs
            // raiz são Hoje / Corpo / Evolução / Ferramentas, e o perfil de
            // acesso vive em Configurações.
            Text("Acesse Configurações → Perfil de acesso para alternar para o perfil médico e habilitar compartilhamento autorizado.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var message: String {
        if activeRole != .clinician {
            return "O perfil atual é \(activeRole.rawValue). Dados clínicos consolidados exigem perfil médico."
        }

        if !hasSharingConsent {
            return "O paciente ainda não autorizou o compartilhamento de relatórios com o médico assistente."
        }

        return "Acesso indisponível."
    }
}

private struct PrivacyStatusGrid: View {
    let consentAccepted: Bool
    let shareWithClinician: Bool
    let shareWithCaregiver: Bool
    let activeRole: AccessRole

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            PrivacyStatusCard(title: "Registro local", isActive: consentAccepted, icon: "tray.and.arrow.down")
            PrivacyStatusCard(title: "Médico", isActive: shareWithClinician, icon: "stethoscope")
            PrivacyStatusCard(title: "Cuidador", isActive: shareWithCaregiver, icon: "person.crop.circle.badge.heart")
            PrivacyStatusCard(title: "Perfil", value: activeRole.rawValue, icon: activeRole.icon)
            PrivacyStatusCard(title: "Dashboard médico", isActive: activeRole == .clinician && shareWithClinician, icon: "stethoscope")
        }
    }
}

private struct PrivacyStatusCard: View {
    let title: String
    var isActive: Bool?
    var value: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(displayValue)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var displayValue: String {
        if let value {
            return value
        }

        return isActive == true ? "Ativo" : "Bloqueado"
    }

    private var color: Color {
        if value != nil {
            return .neuroYellow
        }

        return isActive == true ? .green : .orange
    }
}

private struct RemotePatientSnapshotCard: View {
    let patient: BackendUser
    let checkIns: [BackendDailyCheckIn]
    let assessments: [BackendScaleAssessment]
    let alerts: [BackendClinicalAlert]
    let reports: [BackendClinicalReport]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visão remota")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(patient.fullName)
                        .font(.headline)
                }

                Spacer()

                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundStyle(.orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                StatBadge(title: "Registros", value: "\(checkIns.count)", icon: "calendar")
                StatBadge(title: "Escalas", value: "\(assessments.count)", icon: "checklist.checked")
                StatBadge(title: "Alertas", value: "\(openAlerts.count)", icon: "bell.badge")
                StatBadge(title: "Relatórios", value: "\(reports.count)", icon: "doc.text")
            }

            if let latestCheckIn = checkIns.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Último registro")
                        .font(.subheadline.weight(.semibold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                        Label("Humor \(String(format: "%.1f", latestCheckIn.mood))", systemImage: "face.smiling")
                        Label("Ansiedade \(String(format: "%.1f", latestCheckIn.anxiety))", systemImage: "waveform.path.ecg")
                        Label("Sono \(String(format: "%.1f", latestCheckIn.sleepHours))h", systemImage: "moon.zzz")
                        Label(latestCheckIn.medicationTaken ? "Medicação sim" : "Medicação não", systemImage: "pills")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !assessments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scores recentes")
                        .font(.subheadline.weight(.semibold))

                    ForEach(assessments.prefix(3)) { assessment in
                        HStack {
                            Text(assessment.scaleName)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(assessment.score) · \(assessment.interpretation)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !openAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Alertas abertos")
                        .font(.subheadline.weight(.semibold))

                    ForEach(openAlerts.prefix(3)) { alert in
                        Label(alert.title, systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(alert.level == "high" ? .red : .orange)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var openAlerts: [BackendClinicalAlert] {
        alerts.filter { !$0.acknowledged }
    }
}

private struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct TrendMetricCard: View {
    let title: String
    let icon: String
    let firstValue: Double?
    let latestValue: Double?
    let trend: Double
    let unit: String
    let higherIsBetter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(display(latestValue))
                    .font(.title3.weight(.bold).monospacedDigit())

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(changeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(changeColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("Inicial: \(display(firstValue))\(unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var changeText: String {
        if firstValue == nil || latestValue == nil {
            return "Sem dados suficientes"
        }

        if abs(trend) < 0.05 {
            return "Tendência estável"
        }

        let direction = trend > 0 ? "subindo" : "caindo"
        return "\(direction.capitalized) \(String(format: "%.2f", abs(trend))) por registro"
    }

    private var changeColor: Color {
        if firstValue == nil || latestValue == nil || abs(trend) < 0.05 {
            return .secondary
        }

        let improved = higherIsBetter ? trend > 0 : trend < 0
        return improved ? .green : .orange
    }

    private func display(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "%.1f", value)
    }
}

private struct ClinicalSignal: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CheckInRow: View {
    let checkIn: DailyCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(checkIn.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                Label("Humor \(String(format: "%.1f", checkIn.mood))", systemImage: "face.smiling")
                Label("Ansiedade \(String(format: "%.1f", checkIn.anxiety))", systemImage: "waveform.path.ecg")
                Label("Sono \(String(format: "%.1f", checkIn.sleepHours))h", systemImage: "moon.zzz")
                Label(checkIn.medicationTaken ? "Medicação sim" : "Medicação não", systemImage: "pills")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if checkIn.suicidalIdeation {
                Label("Triagem positiva para ideação suicida", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if !checkIn.sideEffects.isEmpty {
                HistoryNote(title: "Efeitos colaterais", text: checkIn.sideEffects)
            }

            if !checkIn.automaticThoughts.isEmpty {
                HistoryNote(title: "Pensamentos", text: checkIn.automaticThoughts)
            }

            if !checkIn.journalEntry.isEmpty {
                HistoryNote(title: "Diário", text: checkIn.journalEntry)
            }
        }
        .panelStyle()
    }
}

private struct HistoryNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.footnote)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AssessmentRow: View {
    let assessment: ScaleAssessment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(assessment.scaleName)
                    .font(.headline)

                Text("\(assessment.score) pontos · \(assessment.interpretation)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(assessment.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct AlertRow: View {
    let alert: ClinicalAlert
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(alert.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(alert.level == ClinicalRiskLevel.high.rawValue ? .red : .orange)

            Text(alert.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Marcar como revisado", action: acknowledge)
                .buttonStyle(.bordered)
        }
        .panelStyle()
    }
}

private struct ComplianceRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        ClinicalSignal(icon: icon, title: title, description: description)
    }
}

private struct ClinicianPopulationRiskCard: View {
    let signature: NeuroFlowRiskSignature
    let alerts: [ClinicalAlert]
    let checkIns: [DailyCheckIn]
    let remotePatients: [BackendUser]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.3.sequence", title: "Painel populacional")

            Text("No backend real, esta visão ordena pacientes por risco. Localmente ela mostra a lógica aplicada ao paciente atual.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                StatBadge(title: "Risco NeuroFlow", value: "\(signature.score)/100", icon: "brain.head.profile")
                StatBadge(title: "Alertas abertos", value: "\(alerts.count)", icon: "bell.badge")
                StatBadge(title: "Piorou semana", value: worsenedThisWeek ? "Sim" : "Não", icon: "chart.line.downtrend.xyaxis")
                StatBadge(title: "Contato antes consulta", value: shouldContact ? "Priorizar" : "Rotina", icon: "phone.badge.waveform")
                StatBadge(title: "Pacientes remotos", value: "\(remotePatients.count)", icon: "person.2")
                StatBadge(title: "Com risco remoto", value: "\(remotePatients.filter { $0.riskScore != nil }.count)", icon: "list.number")
            }

            if remotePatients.contains(where: { $0.riskScore != nil }) {
                Text("Quando o backend envia `risk_score`, a lista de pacientes é ordenada automaticamente por prioridade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private var worsenedThisWeek: Bool {
        let recent = Array(checkIns.prefix(7))
        guard recent.count >= 3 else { return false }
        return recent.contains { $0.mood <= 2 || $0.anxiety >= 4 || $0.sleepHours < 5 || $0.suicidalIdeation }
    }

    private var shouldContact: Bool {
        signature.level == .high || alerts.contains { $0.level == ClinicalRiskLevel.high.rawValue }
    }
}

private struct ClinicianPreConsultInsightCard: View {
    let summary: LongitudinalSummary
    let checkIns: [DailyCheckIn]
    let assessments: [ScaleAssessment]
    let medicationPlans: [MedicationPlanEntry]
    let signature: NeuroFlowRiskSignature

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "doc.text.magnifyingglass", title: "Resumo pré-consulta")

            Text("Síntese automática para orientar a conversa clínica. Deve ser revisada pelo profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ClinicalSignal(icon: "gauge.with.dots.needle.67percent", title: "Risco atual: \(summary.riskLevel.rawValue)", description: summary.textAssessment.recommendation)
                ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: "Mudança longitudinal", description: longitudinalText)
                ClinicalSignal(icon: "pills", title: "Medicação", description: medicationText)
                ClinicalSignal(icon: "tag", title: "Gatilhos recorrentes", description: triggerText)
                ClinicalSignal(icon: "bandage", title: "Efeitos colaterais recentes", description: sideEffectsText)
                ClinicalSignal(icon: "heart.text.square", title: "Escalas recentes", description: recentScalesText)
                ClinicalSignal(icon: "percent", title: "Sintomas que mais pioraram", description: symptomWorseningText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Perguntas sugeridas")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(suggestedQuestions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .panelStyle()
    }

    private var longitudinalText: String {
        var parts: [String] = []
        if summary.moodTrend < -0.25 {
            parts.append("humor em queda")
        }
        if summary.anxietyTrend > 0.25 {
            parts.append("ansiedade em alta")
        }
        if summary.sleepTrend < -0.25 {
            parts.append("sono reduzindo")
        }
        return parts.isEmpty ? "Sem tendência crítica clara nos registros analisados." : parts.joined(separator: ", ").capitalized + "."
    }

    private var medicationText: String {
        let changes = medicationPlans
            .map(\.changeNote)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !changes.isEmpty {
            return "Há alteração de medicação/dose registrada; revisar temporalidade com sintomas."
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            return "Adesão inferior a 80% nos registros analisados."
        }
        return medicationPlans.isEmpty ? "Nenhuma medicação cadastrada no app." : "Medicações cadastradas sem mudança recente registrada."
    }

    private var triggerText: String {
        let triggers = checkIns.flatMap { triggerLabels(from: $0.journalEntry) }
        guard let mostCommon = Dictionary(grouping: triggers, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }) else {
            return "Ainda não há gatilho recorrente suficiente."
        }
        return "\(mostCommon.key) foi o gatilho mais frequente nos registros com contexto."
    }

    private var sideEffectsText: String {
        let recent = checkIns
            .prefix(7)
            .map(\.sideEffects)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !recent.isEmpty else {
            return "Nenhum efeito colateral recente registrado."
        }
        return Array(Set(recent)).prefix(3).joined(separator: " • ")
    }

    private var recentScalesText: String {
        let recent = assessments.prefix(3)
        guard !recent.isEmpty else {
            return "Nenhuma escala recente salva."
        }
        return recent
            .map { "\($0.scaleName): \($0.score) (\($0.interpretation))" }
            .joined(separator: " • ")
    }

    private var symptomWorseningText: String {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard let first = chronological.first, let latest = chronological.last, chronological.count >= 2 else {
            return "Sem dados suficientes para calcular porcentagem de piora."
        }

        let changes = [
            worseningPercent(title: "ansiedade", first: first.anxiety, latest: latest.anxiety, higherIsWorse: true),
            worseningPercent(title: "irritabilidade", first: first.irritability, latest: latest.irritability, higherIsWorse: true),
            worseningPercent(title: "humor", first: first.mood, latest: latest.mood, higherIsWorse: false),
            worseningPercent(title: "sono", first: first.sleepHours, latest: latest.sleepHours, higherIsWorse: false),
            worseningPercent(title: "energia", first: first.energy, latest: latest.energy, higherIsWorse: false)
        ]
        .compactMap { $0 }
        .sorted { $0.percent > $1.percent }

        guard !changes.isEmpty else {
            return "Sem piora percentual relevante desde o primeiro registro."
        }
        return changes.prefix(3)
            .map { "\($0.title) +\(Int($0.percent.rounded()))%" }
            .joined(separator: " • ")
    }

    private var suggestedQuestions: [String] {
        var questions: [String] = []
        if signature.factors.contains(where: { $0.contains("sono") }) {
            questions.append("O que mudou na rotina de sono nos últimos dias?")
        }
        if signature.factors.contains(where: { $0.contains("medicação") || $0.contains("adesão") }) {
            questions.append("Houve esquecimento, efeito colateral ou dificuldade com a medicação?")
        }
        if signature.factors.contains(where: { $0.contains("gatilhos") }) {
            questions.append("Quais gatilhos apareceram antes dos dias de piora?")
        }
        if sideEffectsText != "Nenhum efeito colateral recente registrado." {
            questions.append("Os efeitos colaterais recentes coincidem com mudança de dose ou adesão?")
        }
        if recentScalesText != "Nenhuma escala recente salva." {
            questions.append("O resultado das escalas confirma o padrão observado no diário?")
        }
        if signature.level == .high {
            questions.append("O plano de segurança está atualizado e acessível?")
        }
        if questions.isEmpty {
            questions.append("O paciente percebe algum padrão que o app ainda não captou?")
        }
        return questions
    }

    private func worseningPercent(title: String, first: Double, latest: Double, higherIsWorse: Bool) -> (title: String, percent: Double)? {
        let delta = higherIsWorse ? latest - first : first - latest
        guard delta > 0 else { return nil }
        let denominator = max(abs(first), 0.5)
        let percent = min((delta / denominator) * 100, 999)
        guard percent >= 10 else { return nil }
        return (title, percent)
    }

    private func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }
}

// P2-3 (UX): adicionado parâmetro opcional `actionLabel`/`action` para
// eliminar dead-ends onde o usuário sabe o que fazer mas não tem caminho
// direto. Usos existentes sem action continuam funcionando.
private struct EmptyState: View {
    let text: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let label = actionLabel, let action {
                Button(action: action) {
                    Label(label, systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .panelStyle()
    }
}

// Sprint 25: barra unificada de busca + filtro por tipo de evento usada na
// Tab Evolução. O TextField roda offline (filtragem em memória) e os chips
// alternam entre check-ins, escalas, alertas ou tudo.
private struct EvolutionSearchFilterCard: View {
    @Binding var query: String
    @Binding var filter: EvolutionFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar no diário, escalas ou alertas", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .accessibilityLabel("Campo de busca da evolução")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EvolutionFilter.allCases) { option in
                        let isSelected = option == filter
                        Button {
                            filter = option
                        } label: {
                            Label(option.rawValue, systemImage: option.icon)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.neuroYellow : Color(.secondarySystemGroupedBackground))
                                .foregroundStyle(isSelected ? Color.black : Color.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filtro \(option.rawValue)")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
        }
        .panelStyle()
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - PatientStore (Sprint E #4)
//
// Cache central para sortedCheckIns / sortedAssessments / summary. Antes do
// refactor essas computeds rodavam ~30 vezes por body (visto em hotspots
// patientEvolutionPage, doctorDashboard, patientToolsPage). Cada chamada
// fazia O(n log n) por causa do .sorted, mais o passo do ClinicalAnalysis.
//
// Estratégia minimalista: `isReady` começa false, fica true após o primeiro
// recompute disparado pelo .task(id: storeFingerprint) no body raiz. Os 3
// callsites originais (sortedCheckIns/sortedAssessments/summary computeds)
// fazem cache-first com fallback ao recompute — não foi preciso mexer nos
// ~30 callsites que consomem essas properties.
//
// Não cacheia `neuroFlowRiskSignature` porque ela depende de inputs voláteis
// (mood/anxiety/ppgStress/voicePauseRatio mudam em tempo real). Mas ela
// automaticamente se beneficia ao consumir o `sortedCheckIns` já cacheado.
@Observable
final class PatientStore {
    private(set) var sortedCheckIns: [DailyCheckIn] = []
    private(set) var sortedAssessments: [ScaleAssessment] = []
    private(set) var activeAlerts: [ClinicalAlert] = []
    private(set) var latestReports: [ClinicalReport] = []
    private(set) var summary: LongitudinalSummary?
    var isReady: Bool { summary != nil }

    func recompute(
        checkIns: [DailyCheckIn],
        assessments: [ScaleAssessment],
        alerts: [ClinicalAlert],
        reports: [ClinicalReport]
    ) {
        let sortedC = checkIns.sorted { $0.date > $1.date }
        let sortedA = assessments.sorted { $0.date > $1.date }
        sortedCheckIns = sortedC
        sortedAssessments = sortedA
        activeAlerts = alerts.filter { !$0.acknowledged }.sorted { $0.date > $1.date }
        latestReports = reports.sorted { $0.date > $1.date }
        summary = ClinicalAnalysis.summary(checkIns: sortedC, assessments: sortedA)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PatientProfile.self, DailyCheckIn.self, ScaleAssessment.self, ClinicalAlert.self, ClinicalReport.self], inMemory: true)
}
