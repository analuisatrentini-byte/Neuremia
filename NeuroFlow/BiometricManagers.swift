//
//  BiometricManagers.swift
//  NeuroFlow
//
//  PPGCameraManager and VoiceSignalManager extracted from ContentView.swift
//  (QC1 decomposition — P3). Both classes are self-contained: they own their
//  AVFoundation sessions and expose only @Published properties to the view layer.
//

import AVFoundation
import Combine

final class PPGCameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isMeasuring = false
    @Published var status = "Pronto para medir com câmera."
    @Published var heartRate = 0.0
    @Published var hrv = 0.0
    @Published var respiration = 0.0
    @Published var perfusion = 0.0
    @Published var stress = 0.0
    @Published var signalQuality = 0.0

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "neuroflow.ppg.camera")
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
        // Clamping would mask bradycardia (<40 BPM) and tachycardia (>160 BPM).
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

final class VoiceSignalManager: NSObject, ObservableObject {
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
        processingQueue.async { [weak self] in
            self?.analyzeSnapshot()
        }
    }

    private func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)

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
