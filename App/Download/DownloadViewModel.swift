//
//  DownloadViewModel.swift
//  yoink
//

import Combine
import Foundation

@MainActor
final class DownloadViewModel: ObservableObject {
    private static let defaultDownloadDirectoryKey = "defaultDownloadDirectory"
    private static let fallbackDownloadDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    private static let ytDlpPathOverrideKey = "ytDlpExecutablePathOverride"
    private static let cookiesBrowserKey = "cookiesBrowser"

    @Published var urlText = ""
    @Published var fileNameText = ""
    @Published var ytDlpExecutablePathText = ""
    @Published var downloads: [DownloadItem] = []

    @Published var selectedMode: DownloadMode = .video
    @Published var availableVideoFormats: [DownloadFormatOption] = [DownloadFormatOption.bestVideo]
    @Published var availableAudioFormats: [DownloadFormatOption] = [DownloadFormatOption.bestAudio]
    @Published var selectedVideoOptionID: String = DownloadFormatOption.bestVideo.id
    @Published var selectedVideoAudioOptionID: String = DownloadFormatOption.bestAudio.id
    @Published var selectedAudioOnlyOptionID: String = DownloadFormatOption.bestAudio.id

    @Published var isAnalyzing = false
    @Published var analysisStatusText = ""
    @Published private(set) var ytDlpPathStatusText = ""
    @Published private(set) var isYtDlpPathValid = false

    private let engine: DownloadEngine
    private var processes: [UUID: Process] = [:]
    private var lastLoggedProgress: [UUID: Double] = [:]
    private var analyzedURL: String?
    private var autoDetectedYtDlpPath: String?

    init(engine: DownloadEngine? = nil) {
        self.engine = engine ?? YtDlpDownloadEngine()
        AppLogger.shared.log("App started")
        autoDetectedYtDlpPath = YtDlpLocator.executableURL()?.path

        let storedOverride = UserDefaults.standard.string(forKey: Self.ytDlpPathOverrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedOverride, !storedOverride.isEmpty {
            ytDlpExecutablePathText = storedOverride
        } else {
            ytDlpExecutablePathText = autoDetectedYtDlpPath ?? ""
        }

        refreshYtDlpPathStatus()

        if let resolved = autoDetectedYtDlpPath {
            AppLogger.shared.log("yt-dlp locator resolved executable: \(resolved)")
        } else {
            AppLogger.shared.log("yt-dlp locator failed. \(YtDlpLocator.discoveryReport(preferredPath: ytDlpExecutablePathText))")
        }

        if let ffmpegPath = FFmpegLocator.executableURL()?.path {
            AppLogger.shared.log("ffmpeg locator resolved executable: \(ffmpegPath)")
        } else {
            AppLogger.shared.log("ffmpeg locator failed. \(FFmpegLocator.discoveryReport())")
        }

        if let denoPath = DenoLocator.executableURL()?.path {
            AppLogger.shared.log("deno locator resolved executable: \(denoPath)")
        } else {
            AppLogger.shared.log("deno locator failed. \(DenoLocator.discoveryReport())")
            if let nodePath = NodeLocator.executableURL()?.path {
                AppLogger.shared.log("node locator resolved executable: \(nodePath)")
            } else {
                AppLogger.shared.log("node locator failed. \(NodeLocator.discoveryReport())")
            }
        }
    }

    func startDownload() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let customFileName = fileNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let overrideFileName = customFileName.isEmpty ? nil : customFileName
        let ytDlpPathOverride = normalizedYtDlpPathOverride()

        let selectedVideoFormat = selectedVideoFormatForCurrentState(url: trimmed)
        let selectedAudioFormat = selectedAudioFormatForCurrentState(url: trimmed)
        let cookiesBrowser = CookiesBrowser(
            rawValue: UserDefaults.standard.string(forKey: Self.cookiesBrowserKey) ?? ""
        ) ?? .none

        let request = DownloadRequest(
            url: trimmed,
            mode: selectedMode,
            selectedVideoFormat: selectedVideoFormat,
            selectedAudioFormat: selectedAudioFormat,
            customFileName: overrideFileName,
            ytDlpExecutablePathOverride: ytDlpPathOverride,
            cookiesBrowser: cookiesBrowser
        )

        var item = DownloadItem(url: trimmed, mode: selectedMode, status: .queued, progress: 0.0)
        item.fileName = overrideFileName
        downloads.insert(item, at: 0)

        if let overrideFileName {
            AppLogger.shared.log("Download queued: \(trimmed), mode: \(selectedMode.displayName), video-format: \(selectedVideoFormat.displayName), audio-format: \(selectedAudioFormat.displayName), file-name override: \(overrideFileName)")
        } else {
            AppLogger.shared.log("Download queued: \(trimmed), mode: \(selectedMode.displayName), video-format: \(selectedVideoFormat.displayName), audio-format: \(selectedAudioFormat.displayName)")
        }

        urlText = ""
        fileNameText = ""
        analysisStatusText = ""

        runDownload(for: item.id, request: request)
    }

    func analyzeFormats() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ytDlpPathOverride = normalizedYtDlpPathOverride()

        isAnalyzing = true
        analysisStatusText = "Analyzing formats..."
        AppLogger.shared.log("Format analysis started: \(trimmed)")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                let parsed = try Self.analyzeFormatsSync(url: trimmed, ytDlpPathOverride: ytDlpPathOverride)

                await MainActor.run {
                    self.isAnalyzing = false
                    self.availableVideoFormats = [DownloadFormatOption.bestVideo] + parsed.videoOptions
                    self.availableAudioFormats = [DownloadFormatOption.bestAudio] + parsed.audioOptions

                    if !self.availableVideoFormats.contains(where: { $0.id == self.selectedVideoOptionID }) {
                        self.selectedVideoOptionID = DownloadFormatOption.bestVideo.id
                    }
                    if !self.availableAudioFormats.contains(where: { $0.id == self.selectedVideoAudioOptionID }) {
                        self.selectedVideoAudioOptionID = DownloadFormatOption.bestAudio.id
                    }
                    if !self.availableAudioFormats.contains(where: { $0.id == self.selectedAudioOnlyOptionID }) {
                        self.selectedAudioOnlyOptionID = DownloadFormatOption.bestAudio.id
                    }

                    self.analyzedURL = trimmed
                    let videoCount = max(0, self.availableVideoFormats.count - 1)
                    let audioCount = max(0, self.availableAudioFormats.count - 1)
                    self.analysisStatusText = "Found \(videoCount) video + \(audioCount) audio formats"
                    AppLogger.shared.log("Format analysis completed: \(trimmed), video: \(videoCount), audio: \(audioCount)")
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    self.isAnalyzing = false
                    self.availableVideoFormats = [DownloadFormatOption.bestVideo]
                    self.availableAudioFormats = [DownloadFormatOption.bestAudio]
                    self.selectedVideoOptionID = DownloadFormatOption.bestVideo.id
                    self.selectedVideoAudioOptionID = DownloadFormatOption.bestAudio.id
                    self.selectedAudioOnlyOptionID = DownloadFormatOption.bestAudio.id
                    self.analyzedURL = nil
                    self.analysisStatusText = "Analyze failed: \(message)"
                    AppLogger.shared.log("Format analysis failed: \(trimmed), reason: \(message)")
                }
            }
        }
    }

    func onYtDlpPathChanged() {
        refreshYtDlpPathStatus()
    }

    func onURLChanged() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let analyzedURL, analyzedURL != trimmed else { return }
        resetAnalyzedFormats()
    }

    func useAutoDetectedYtDlpPath() {
        ytDlpExecutablePathText = autoDetectedYtDlpPath ?? ""
        refreshYtDlpPathStatus()
    }

    private func runDownload(for id: UUID, request: DownloadRequest) {
        let downloadDirectory = resolvedDownloadDirectory()

        do {
            let process = try engine.startDownload(
                id: id,
                request: request,
                destinationDirectory: downloadDirectory
            ) { [weak self] eventID, event in
                self?.handleEngineEvent(eventID: eventID, event: event, url: request.url)
            }
            processes[id] = process
            AppLogger.shared.log("\(engine.name) started for: \(request.url), mode: \(request.mode.displayName), destination: \(downloadDirectory)")
        } catch {
            updateStatus(id: id, status: .failed, reason: error.localizedDescription)
            AppLogger.shared.log("\(engine.name) failed to start for: \(request.url). Error: \(error.localizedDescription)")
            processes[id] = nil
        }
    }

    private func selectedVideoFormatForCurrentState(url: String) -> DownloadFormatOption {
        if selectedMode == .audio {
            return DownloadFormatOption.bestVideo
        }
        return resolveSelection(
            options: availableVideoFormats,
            selectedID: selectedVideoOptionID,
            fallback: DownloadFormatOption.bestVideo,
            url: url
        )
    }

    private func selectedAudioFormatForCurrentState(url: String) -> DownloadFormatOption {
        let selectedID = selectedMode == .video ? selectedVideoAudioOptionID : selectedAudioOnlyOptionID
        return resolveSelection(
            options: availableAudioFormats,
            selectedID: selectedID,
            fallback: DownloadFormatOption.bestAudio,
            url: url
        )
    }

    private func resolveSelection(
        options: [DownloadFormatOption],
        selectedID: String,
        fallback: DownloadFormatOption,
        url: String
    ) -> DownloadFormatOption {
        let current = options.first(where: { $0.id == selectedID }) ?? fallback
        guard current.formatID != nil else {
            return current
        }
        if analyzedURL == url {
            return current
        }
        AppLogger.shared.log("Selected analyzed format ignored because URL changed. Falling back to best available.")
        return fallback
    }

    private func resolvedDownloadDirectory() -> String {
        let configured = UserDefaults.standard.string(forKey: Self.defaultDownloadDirectoryKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configured, !configured.isEmpty else {
            return Self.fallbackDownloadDirectory
        }
        return configured
    }

    private func normalizedYtDlpPathOverride() -> String? {
        let trimmed = ytDlpExecutablePathText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resetAnalyzedFormats() {
        availableVideoFormats = [DownloadFormatOption.bestVideo]
        availableAudioFormats = [DownloadFormatOption.bestAudio]
        selectedVideoOptionID = DownloadFormatOption.bestVideo.id
        selectedVideoAudioOptionID = DownloadFormatOption.bestAudio.id
        selectedAudioOnlyOptionID = DownloadFormatOption.bestAudio.id
        analyzedURL = nil
    }

    private func refreshYtDlpPathStatus() {
        autoDetectedYtDlpPath = YtDlpLocator.executableURL()?.path
        let normalized = normalizedYtDlpPathOverride()
        let manualOverrideInUse: String?
        if let normalized, normalized != autoDetectedYtDlpPath {
            manualOverrideInUse = normalized
        } else {
            manualOverrideInUse = nil
        }
        let pathInUse = manualOverrideInUse ?? autoDetectedYtDlpPath

        if let pathInUse {
            let exists = FileManager.default.fileExists(atPath: pathInUse)
            isYtDlpPathValid = exists
            if exists {
                if manualOverrideInUse != nil {
                    ytDlpPathStatusText = "Manual path in use"
                } else {
                    ytDlpPathStatusText = "Auto detected"
                }
            } else {
                ytDlpPathStatusText = "Path not found: \(pathInUse)"
            }
        } else {
            isYtDlpPathValid = false
            ytDlpPathStatusText = "yt-dlp not found automatically. Set path manually, or run `brew install yt-dlp` in Terminal. Then restart the app and press \"Use Auto Detected\"."
        }

        if let manualOverrideInUse {
            UserDefaults.standard.set(manualOverrideInUse, forKey: Self.ytDlpPathOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.ytDlpPathOverrideKey)
        }
    }

    private func handleEngineEvent(eventID: UUID, event: DownloadEngineEvent, url: String) {
        switch event {
        case .status(let status):
            updateStatus(id: eventID, status: status, reason: nil)
        case .destinationFileName(let fileName):
            updateFileName(id: eventID, fileName: fileName)
        case .progress(let progress):
            updateProgress(id: eventID, progress: progress)
            if progress < 1.0 {
                updateStatus(id: eventID, status: .downloading, reason: nil)
            }
        case .speed(let speedText):
            updateSpeed(id: eventID, speedText: speedText)
        case .eta(let etaText):
            updateEta(id: eventID, etaText: etaText)
        case .fileSize(let sizeText):
            updateFileSize(id: eventID, sizeText: sizeText)
        case .finished(let exitCode, let skipped, let message):
            processes[eventID] = nil
            if exitCode == 0 {
                if skipped {
                    updateProgress(id: eventID, progress: 1.0, shouldLog: false)
                    updateStatus(id: eventID, status: .skipped, reason: message)
                    if let message, !message.isEmpty {
                        AppLogger.shared.log("\(engine.name) skipped download for: \(url). Reason: \(message)")
                    } else {
                        AppLogger.shared.log("\(engine.name) skipped download for: \(url)")
                    }
                } else {
                    updateProgress(id: eventID, progress: 1.0, shouldLog: false)
                    updateStatus(id: eventID, status: .done, reason: nil)
                    AppLogger.shared.log("\(engine.name) finished successfully for: \(url)")
                }
            } else {
                updateStatus(id: eventID, status: .failed, reason: message)
                if let message, !message.isEmpty {
                    AppLogger.shared.log("\(engine.name) failed for: \(url). Exit code: \(exitCode). Reason: \(message)")
                } else {
                    AppLogger.shared.log("\(engine.name) failed for: \(url). Exit code: \(exitCode)")
                }
            }
        }
    }

    private func updateStatus(id: UUID, status: DownloadStatus, reason: String?) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        if downloads[index].status == status, downloads[index].statusReason == reason {
            return
        }
        downloads[index].status = status
        downloads[index].statusReason = reason
        AppLogger.shared.log("Status updated: \(downloads[index].url) → \(status.displayName)")
    }

    private func updateProgress(id: UUID, progress: Double, shouldLog: Bool = true) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].progress = progress
        if shouldLog {
            logProgressIfNeeded(id: id, progress: progress, url: downloads[index].url)
        }
    }

    private func updateFileName(id: UUID, fileName: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].fileName = fileName
        AppLogger.shared.log("Resolved output file name: \(downloads[index].url) → \(fileName)")
    }

    private func updateSpeed(id: UUID, speedText: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        if downloads[index].speedText == speedText {
            return
        }
        downloads[index].speedText = speedText
    }

    private func updateEta(id: UUID, etaText: String?) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        if downloads[index].etaText == etaText { return }
        downloads[index].etaText = etaText
    }

    private func updateFileSize(id: UUID, sizeText: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        if downloads[index].fileSizeText == sizeText { return }
        downloads[index].fileSizeText = sizeText
    }

    private func logProgressIfNeeded(id: UUID, progress: Double, url: String) {
        let normalized = max(0.0, min(1.0, progress))
        let last = lastLoggedProgress[id] ?? -1.0
        if normalized >= 1.0 {
            // hlsnative can report transient 100% before completion.
            // While process is still running, ignore such events for logging.
            if processes[id] != nil {
                return
            }
            // Prevent repeated "100%" log spam from multiple terminal progress events.
            if last < 1.0 {
                lastLoggedProgress[id] = 1.0
                AppLogger.shared.log("Progress: \(url) → 100%")
            }
            return
        }

        if normalized - last >= 0.05 {
            lastLoggedProgress[id] = normalized
            let percent = Int(normalized * 100)
            AppLogger.shared.log("Progress: \(url) → \(percent)%")
        }
    }

    nonisolated private static func analyzeFormatsSync(url: String, ytDlpPathOverride: String?) throws -> (videoOptions: [DownloadFormatOption], audioOptions: [DownloadFormatOption]) {
        let analyzeArgs = ["-J", "--no-warnings", "--skip-download", url]
        guard let invocation = YtDlpLocator.invocationArguments(for: analyzeArgs, preferredPath: ytDlpPathOverride) else {
            throw NSError(
                domain: "YtDlpError",
                code: 127,
                userInfo: [NSLocalizedDescriptionKey: "yt-dlp executable not found. \(YtDlpLocator.discoveryReport(preferredPath: ytDlpPathOverride))"]
            )
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw NSError(
                domain: "FormatAnalyzeError",
                code: 128,
                userInfo: [NSLocalizedDescriptionKey: "launch failed: \(error.localizedDescription); \(invocation.launchReport)"]
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "FormatAnalyzeError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "yt-dlp exited with code \(process.terminationStatus)"]
            )
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formats = jsonObject["formats"] as? [[String: Any]] else {
            throw NSError(domain: "FormatAnalyzeError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to parse format list"])
        }

        var videoOptions: [DownloadFormatOption] = []
        var audioOptions: [DownloadFormatOption] = []

        for format in formats {
            guard let formatID = format["format_id"] as? String, !formatID.isEmpty else { continue }

            let ext = (format["ext"] as? String ?? "unknown").lowercased()
            let vcodec = (format["vcodec"] as? String ?? "none").lowercased()
            let acodec = (format["acodec"] as? String ?? "none").lowercased()

            if vcodec != "none" && acodec == "none" {
                let height = format["height"] as? Int
                let fps = format["fps"] as? Double
                let resolutionText = height.map { "\($0)p" } ?? "video"
                let fpsText: String
                if let fps {
                    fpsText = ", \(Int(fps))fps"
                } else {
                    fpsText = ""
                }

                let title = "\(ext) \(resolutionText)\(fpsText)"

                videoOptions.append(
                    DownloadFormatOption(
                        id: "video-\(formatID)",
                        formatID: formatID,
                        container: nil,
                        displayName: "\(title) (id: \(formatID))"
                    )
                )
            }

            if acodec != "none" && vcodec == "none" {
                let abr = (format["abr"] as? Double) ?? (format["tbr"] as? Double)
                let bitrateText = abr.map { "\(Int($0))k" } ?? "audio"
                let title = "\(ext) \(bitrateText)"

                audioOptions.append(
                    DownloadFormatOption(
                        id: "audio-\(formatID)",
                        formatID: formatID,
                        container: ext,
                        displayName: "\(title) (id: \(formatID))"
                    )
                )
            }
        }

        videoOptions = deduplicatedAndSorted(options: videoOptions)
        audioOptions = deduplicatedAndSorted(options: audioOptions)

        return (videoOptions: videoOptions, audioOptions: audioOptions)
    }

    nonisolated private static func deduplicatedAndSorted(options: [DownloadFormatOption]) -> [DownloadFormatOption] {
        var seen: Set<String> = []
        var unique: [DownloadFormatOption] = []

        for option in options where !seen.contains(option.id) {
            seen.insert(option.id)
            unique.append(option)
        }

        return unique.sorted { $0.displayName < $1.displayName }
    }
}
