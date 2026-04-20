//
//  DownloadEngine.swift
//  yoink
//

import Foundation

protocol DownloadEngine {
    var name: String { get }

    func startDownload(
        id: UUID,
        request: DownloadRequest,
        destinationDirectory: String,
        onEvent: @escaping (UUID, DownloadEngineEvent) -> Void
    ) throws -> Process
}

enum YtDlpLocator {
    nonisolated static let commonPaths: [String] = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/opt/local/bin/yt-dlp",
        "/usr/bin/yt-dlp"
    ]

    nonisolated static func executableURL(preferredPath: String? = nil) -> URL? {
        let fm = FileManager.default
        if let preferredPath {
            let trimmed = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, fm.fileExists(atPath: trimmed) {
                return URL(fileURLWithPath: trimmed).resolvingSymlinksInPath()
            }
        }
        for path in commonPaths where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return nil
    }

    nonisolated static func invocationArguments(for baseArguments: [String], preferredPath: String? = nil) -> (executableURL: URL, arguments: [String], launchReport: String)? {
        guard let scriptURL = executableURL(preferredPath: preferredPath) else { return nil }

        // Homebrew yt-dlp typically ships as a Python script in libexec/bin.
        // Prefer sibling "python" interpreter when present to avoid script exec failures in GUI context.
        let siblingPythonURL = scriptURL.deletingLastPathComponent().appendingPathComponent("python")
        if FileManager.default.fileExists(atPath: siblingPythonURL.path) {
            let args = [scriptURL.path] + baseArguments
            return (
                executableURL: siblingPythonURL,
                arguments: args,
                launchReport: "launcher: \(siblingPythonURL.path), script: \(scriptURL.path)"
            )
        }

        if let interpreterPath = shebangInterpreterPath(for: scriptURL.path),
           FileManager.default.fileExists(atPath: interpreterPath) {
            let args = [scriptURL.path] + baseArguments
            return (
                executableURL: URL(fileURLWithPath: interpreterPath),
                arguments: args,
                launchReport: "launcher: \(interpreterPath), script: \(scriptURL.path)"
            )
        }

        return (
            executableURL: scriptURL,
            arguments: baseArguments,
            launchReport: "launcher: direct-script, script: \(scriptURL.path)"
        )
    }

    nonisolated static func discoveryReport(preferredPath: String? = nil) -> String {
        let fm = FileManager.default
        var parts: [String] = []
        if let preferredPath {
            let trimmed = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let exists = fm.fileExists(atPath: trimmed)
                let executable = fm.isExecutableFile(atPath: trimmed)
                parts.append("preferred:\(trimmed) [exists:\(exists), exec:\(executable)]")
            }
        }
        parts += commonPaths.map { path in
            let exists = fm.fileExists(atPath: path)
            let executable = fm.isExecutableFile(atPath: path)
            return "\(path) [exists:\(exists), exec:\(executable)]"
        }
        return parts.joined(separator: "; ")
    }

    nonisolated private static func shebangInterpreterPath(for scriptPath: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: scriptPath) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 256)
        guard let line = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).first,
              line.hasPrefix("#!") else {
            return nil
        }

        let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return content.components(separatedBy: .whitespaces).first
    }
}

enum FFmpegLocator {
    nonisolated static let commonPaths: [String] = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    nonisolated static func executableURL() -> URL? {
        let fm = FileManager.default
        for path in commonPaths where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return nil
    }

    nonisolated static func discoveryReport() -> String {
        let fm = FileManager.default
        return commonPaths.map { path in
            let exists = fm.fileExists(atPath: path)
            let executable = fm.isExecutableFile(atPath: path)
            return "\(path) [exists:\(exists), exec:\(executable)]"
        }.joined(separator: "; ")
    }
}

enum DenoLocator {
    nonisolated static let commonPaths: [String] = [
        "/opt/homebrew/bin/deno",
        "/usr/local/bin/deno",
        "/opt/local/bin/deno",
        "/usr/bin/deno"
    ]

    nonisolated static func executableURL() -> URL? {
        let fm = FileManager.default
        for path in commonPaths where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return nil
    }

    nonisolated static func discoveryReport() -> String {
        let fm = FileManager.default
        return commonPaths.map { path in
            let exists = fm.fileExists(atPath: path)
            let executable = fm.isExecutableFile(atPath: path)
            return "\(path) [exists:\(exists), exec:\(executable)]"
        }.joined(separator: "; ")
    }
}

enum NodeLocator {
    nonisolated static let commonPaths: [String] = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/opt/local/bin/node",
        "/usr/bin/node"
    ]

    nonisolated static func executableURL() -> URL? {
        let fm = FileManager.default
        for path in commonPaths where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return nil
    }

    nonisolated static func discoveryReport() -> String {
        let fm = FileManager.default
        return commonPaths.map { path in
            let exists = fm.fileExists(atPath: path)
            let executable = fm.isExecutableFile(atPath: path)
            return "\(path) [exists:\(exists), exec:\(executable)]"
        }.joined(separator: "; ")
    }
}

final class YtDlpDownloadEngine: DownloadEngine {
    var name: String { "yt-dlp" }

    private struct ProgressLineData {
        let progress: Double
        let fileSizeText: String
        let speedText: String
        let etaText: String?
    }

    // yt-dlp progress line format:
    //   [download]   0.4% of    7.04MiB at  406.86KiB/s ETA 00:17
    //   [download] 100% of    7.04MiB in 00:17 at  438.13KiB/s
    private static let progressLineRegex =
        /\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+\s*(?:GiB|MiB|KiB|TiB|GB|MB|KB|TB|B)).*?at\s+(\S+)(?:.*?ETA\s+(\d{1,2}:\d{2}))?/

    func startDownload(
        id: UUID,
        request: DownloadRequest,
        destinationDirectory: String,
        onEvent: @escaping (UUID, DownloadEngineEvent) -> Void
    ) throws -> Process {
        let ytDlpArgs = ytDlpArguments(for: request, destinationDirectory: destinationDirectory)
        guard let invocation = YtDlpLocator.invocationArguments(
            for: ytDlpArgs,
            preferredPath: request.ytDlpExecutablePathOverride
        ) else {
            throw NSError(
                domain: "YtDlpError",
                code: 127,
                userInfo: [NSLocalizedDescriptionKey: "yt-dlp executable not found. \(YtDlpLocator.discoveryReport(preferredPath: request.ytDlpExecutablePathOverride))"]
            )
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let outputStateLock = NSLock()
        var skippedExistingFile = false
        var fullOutput = ""
        var lastResolvedDestinationFileName: String?
        var lastEmittedSpeedText: String?
        var lastEmittedEtaText: String?
        var lastEmittedFileSizeText: String?

        let renderedCommand = renderShellCommand(
            executablePath: invocation.executableURL.path,
            arguments: invocation.arguments
        )
        AppLogger.shared.log("\(name) launch command: \(renderedCommand)")
        AppLogger.shared.log("\(name) launch report: \(invocation.launchReport)")

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            outputStateLock.lock()
            fullOutput.append(text)
            outputStateLock.unlock()

            let lower = text.lowercased()
            if lower.contains("has already been downloaded")
                || lower.contains("already exists")
                || lower.contains("has already been recorded in the archive") {
                outputStateLock.lock()
                skippedExistingFile = true
                outputStateLock.unlock()
            }

            if let destinationFileName = self.extractDestinationFileName(from: text) {
                outputStateLock.lock()
                let shouldEmit = destinationFileName != lastResolvedDestinationFileName
                if shouldEmit {
                    lastResolvedDestinationFileName = destinationFileName
                }
                outputStateLock.unlock()

                if shouldEmit {
                    DispatchQueue.main.async {
                        onEvent(id, .destinationFileName(destinationFileName))
                    }
                }
            }

            if let lineData = self.extractProgressLine(from: text) {
                let speedText = lineData.speedText
                outputStateLock.lock()
                let shouldEmitSpeed = speedText != lastEmittedSpeedText
                if shouldEmitSpeed { lastEmittedSpeedText = speedText }
                outputStateLock.unlock()
                if shouldEmitSpeed {
                    DispatchQueue.main.async { onEvent(id, .speed(speedText)) }
                }

                let sizeText = lineData.fileSizeText
                outputStateLock.lock()
                let shouldEmitSize = sizeText != lastEmittedFileSizeText
                if shouldEmitSize { lastEmittedFileSizeText = sizeText }
                outputStateLock.unlock()
                if shouldEmitSize {
                    DispatchQueue.main.async { onEvent(id, .fileSize(sizeText)) }
                }

                if let etaText = lineData.etaText {
                    outputStateLock.lock()
                    let shouldEmitEta = etaText != lastEmittedEtaText
                    if shouldEmitEta { lastEmittedEtaText = etaText }
                    outputStateLock.unlock()
                    if shouldEmitEta {
                        DispatchQueue.main.async { onEvent(id, .eta(etaText)) }
                    }
                }

                DispatchQueue.main.async {
                    onEvent(id, .progress(lineData.progress))
                }
            }
        }

        process.terminationHandler = { proc in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            outputStateLock.lock()
            let skipped = skippedExistingFile
            let capturedOutput = fullOutput
            let resolvedFileName = lastResolvedDestinationFileName
            outputStateLock.unlock()
            AppLogger.shared.log("\(self.name) full output for: \(request.url)\n\(capturedOutput)")
            let message: String?
            if skipped {
                message = self.extractSkippedReason(from: capturedOutput) ?? "File already exists"
            } else if proc.terminationStatus == 0 {
                message = nil
            } else {
                message = self.extractFailureReason(from: capturedOutput)
            }
            DispatchQueue.main.async {
                onEvent(id, .eta(nil))
            }
            if proc.terminationStatus == 0, !skipped, let fileName = resolvedFileName {
                let fullPath = (destinationDirectory as NSString).appendingPathComponent(fileName)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                   let fileSize = attrs[.size] as? Int64 {
                    let formatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                    DispatchQueue.main.async {
                        onEvent(id, .fileSize(formatted))
                    }
                }
            }
            DispatchQueue.main.async {
                onEvent(id, .finished(proc.terminationStatus, skipped: skipped, message: message))
            }
        }

        do {
            try process.run()
        } catch {
            throw NSError(
                domain: "YtDlpError",
                code: 128,
                userInfo: [NSLocalizedDescriptionKey: "launch failed: \(error.localizedDescription); \(invocation.launchReport)"]
            )
        }

        DispatchQueue.main.async {
            onEvent(id, .status(.downloading))
        }

        return process
    }

    private func ytDlpArguments(for request: DownloadRequest, destinationDirectory: String) -> [String] {
        var args = [
            "-P", destinationDirectory,
            "--no-overwrites",
            "--no-post-overwrites"
        ]

        if request.cookiesBrowser != .none {
            let browserValue: String
            if let profile = request.cookiesBrowserProfile,
               !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                browserValue = "\(request.cookiesBrowser.rawValue):\(profile.trimmingCharacters(in: .whitespacesAndNewlines))"
            } else {
                browserValue = request.cookiesBrowser.rawValue
            }
            args += ["--cookies-from-browser", browserValue]
        }

        if let ffmpegPath = FFmpegLocator.executableURL()?.path {
            args += ["--ffmpeg-location", ffmpegPath]
        }
        if let denoPath = DenoLocator.executableURL()?.path {
            args += ["--js-runtimes", "deno:\(denoPath)"]
        } else if let nodePath = NodeLocator.executableURL()?.path {
            args += ["--js-runtimes", "node:\(nodePath)"]
        }

        if let customFileName = request.customFileName {
            args += ["-o", resolvedCustomOutputTemplate(customFileName)]
        } else {
            args += ["-o", "%(title)s [%(id)s].%(ext)s"]
        }

        switch request.mode {
        case .video:
            let selectedVideoID = request.selectedVideoFormat.formatID
            let selectedAudioID = request.selectedAudioFormat.formatID

            if let selectedVideoID {
                if let selectedAudioID {
                    args += ["-f", "\(selectedVideoID)+\(selectedAudioID)"]
                } else {
                    args += ["-f", "\(selectedVideoID)+ba[ext=m4a]/\(selectedVideoID)+ba/\(selectedVideoID)"]
                }
            } else {
                // Keep legacy default behavior for non-analyzed "Best available":
                // prefer a single pre-merged stream instead of forced separate video+audio merge.
                args += ["-f", "b[ext=mp4]/b"]
            }
            args += [request.url]
        case .audio:
            if let formatID = request.selectedAudioFormat.formatID {
                args += ["-f", formatID]
            }
            let audioContainer = request.selectedAudioFormat.container ?? "mp3"
            args += ["-x", "--audio-format", audioContainer, request.url]
        }

        return args
    }

    private func resolvedCustomOutputTemplate(_ rawName: String) -> String {
        // Keep advanced yt-dlp templates untouched.
        if rawName.contains("%(") {
            return rawName
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "%(title)s [%(id)s].%(ext)s" }

        let nsName = trimmed as NSString
        let providedExt = nsName.pathExtension
        let hasExtension = !providedExt.isEmpty
        let baseName = hasExtension ? nsName.deletingPathExtension : trimmed
        let safeBase = baseName.isEmpty ? "download" : baseName
        let normalizedExt = providedExt.lowercased()

        if hasExtension {
            return "\(safeBase).\(normalizedExt)"
        } else {
            return "\(safeBase).%(ext)s"
        }
    }

    private func renderShellCommand(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments).map(shellQuote).joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func extractSkippedReason(from output: String) -> String? {
        for line in output.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if lower.contains("already exists")
                || lower.contains("already been downloaded")
                || lower.contains("already been recorded in the archive") {
                return trimmed
            }
        }
        return nil
    }

    private func extractFailureReason(from output: String) -> String? {
        for line in output.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("ERROR:")
                || trimmed.hasPrefix("Error:")
                || trimmed.hasPrefix("error:") {
                return trimmed
            }
        }

        for line in output.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func extractDestinationFileName(from outputChunk: String) -> String? {
        for line in outputChunk.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let range = trimmed.range(of: "[download] Destination: ") {
                let fullPath = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !fullPath.isEmpty {
                    return URL(fileURLWithPath: fullPath).lastPathComponent
                }
            }

            if let range = trimmed.range(of: "[Merger] Merging formats into \"") {
                let tail = String(trimmed[range.upperBound...])
                if let closingQuote = tail.firstIndex(of: "\"") {
                    let fullPath = String(tail[..<closingQuote])
                    if !fullPath.isEmpty {
                        return URL(fileURLWithPath: fullPath).lastPathComponent
                    }
                }
            }

            if let range = trimmed.range(of: "[download] "),
               let suffixRange = trimmed.range(of: " has already been downloaded") {
                let fullPath = String(trimmed[range.upperBound..<suffixRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !fullPath.isEmpty {
                    return URL(fileURLWithPath: fullPath).lastPathComponent
                }
            }
        }
        return nil
    }

    private func extractProgressLine(from outputChunk: String) -> ProgressLineData? {
        let lines = outputChunk
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)

        var fallback: ProgressLineData? = nil

        for line in lines.reversed() {
            guard line.contains("[download]"), line.contains("%") else { continue }
            guard let match = line.firstMatch(of: Self.progressLineRegex) else { continue }
            let output = match.output
            guard let percent = Double(output.1) else { continue }

            let data = ProgressLineData(
                progress: max(0.0, min(1.0, percent / 100.0)),
                fileSizeText: String(output.2).trimmingCharacters(in: .whitespacesAndNewlines),
                speedText: String(output.3).trimmingCharacters(in: .whitespacesAndNewlines),
                etaText: output.4.map { String($0) }
            )

            // hlsnative may emit a transient "100.0%" early and then continue with lower values.
            // Prefer the last non-100% line in the chunk; fall back to the last line otherwise.
            if percent < 100.0 { return data }
            if fallback == nil { fallback = data }
        }

        return fallback
    }
}
