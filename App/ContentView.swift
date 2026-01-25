//
//  ContentView.swift
//  yoink
//
//  Created by user on 20.01.2026.
//

import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()

    var body: some View {
        VStack(spacing: 16) {
            GroupBox("Download") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Enter URL", text: $viewModel.urlText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Download") {
                            viewModel.startDownload()
                        }
                        .disabled(viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(8)
            }

            GroupBox("Downloads") {
                if viewModel.downloads.isEmpty {
                    Text("No downloads yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                } else {
                    ScrollView {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("URL").bold()
                                Text("Status").bold()
                                Text("Progress").bold()
                                Text("Added").bold()
                            }
                            Divider()
                                .gridCellColumns(4)

                            ForEach(viewModel.downloads) { item in
                                GridRow {
                                    Text(item.url)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.status.displayName)
                                        .foregroundStyle(item.status.color)
                                        .frame(minWidth: 96, alignment: .leading)
                                    HStack(spacing: 8) {
                                        ProgressView(value: item.progress)
                                            .frame(minWidth: 80)
                                        Text("\(Int(item.progress * 100))%")
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 44, alignment: .trailing)
                                    }
                                    Text(item.addedText)
                                        .frame(minWidth: 140, alignment: .leading)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

private struct DownloadItem: Identifiable {
    let id = UUID()
    let url: String
    var status: DownloadStatus
    var progress: Double
    let addedText: String

    init(url: String, status: DownloadStatus, progress: Double) {
        self.url = url
        self.status = status
        self.progress = progress
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        self.addedText = formatter.string(from: Date())
    }
}

private enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case done = "Done"
    case failed = "Failed"

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .queued:
            return .secondary
        case .downloading:
            return .blue
        case .done:
            return .green
        case .failed:
            return .red
        }
    }
}

@MainActor
private final class DownloadViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var downloads: [DownloadItem] = []

    private var processes: [UUID: Process] = [:]
    private var lastLoggedProgress: [UUID: Double] = [:]

    init() {
        AppLogger.shared.log("App started")
    }

    func startDownload() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = DownloadItem(url: trimmed, status: .queued, progress: 0.0)
        downloads.insert(item, at: 0)
        AppLogger.shared.log("Download queued: \(trimmed)")
        urlText = ""
        runYtDlp(for: item.id, url: trimmed)
    }

    private func runYtDlp(for id: UUID, url: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp", url]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        updateStatus(id: id, status: .downloading)
        AppLogger.shared.log("yt-dlp started for: \(url)")
        processes[id] = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.handleOutput(text, for: id)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.processes[id] = nil
                if proc.terminationStatus == 0 {
                    self.updateProgress(id: id, progress: 1.0)
                    self.updateStatus(id: id, status: .done)
                    AppLogger.shared.log("yt-dlp finished successfully for: \(url)")
                } else {
                    self.updateStatus(id: id, status: .failed)
                    AppLogger.shared.log("yt-dlp failed for: \(url). Exit code: \(proc.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            updateStatus(id: id, status: .failed)
            AppLogger.shared.log("yt-dlp failed to start for: \(url). Error: \(error.localizedDescription)")
            processes[id] = nil
        }
    }

    private func handleOutput(_ text: String, for id: UUID) {
        let pattern = "\\[download\\]\\s+([0-9.]+)%"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let percentRange = Range(match.range(at: 1), in: text),
           let percent = Double(text[percentRange]) {
            let progress = max(0.0, min(1.0, percent / 100.0))
            DispatchQueue.main.async {
                self.updateProgress(id: id, progress: progress)
                if progress < 1.0 {
                    self.updateStatus(id: id, status: .downloading)
                }
            }
        }
    }

    private func updateStatus(id: UUID, status: DownloadStatus) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].status = status
        AppLogger.shared.log("Status updated: \(downloads[index].url) → \(status.displayName)")
    }

    private func updateProgress(id: UUID, progress: Double) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].progress = progress
        logProgressIfNeeded(id: id, progress: progress, url: downloads[index].url)
    }

    private func logProgressIfNeeded(id: UUID, progress: Double, url: String) {
        let normalized = max(0.0, min(1.0, progress))
        let last = lastLoggedProgress[id] ?? -1.0
        if normalized >= 1.0 || normalized - last >= 0.05 {
            lastLoggedProgress[id] = normalized
            let percent = Int(normalized * 100)
            AppLogger.shared.log("Progress: \(url) → \(percent)%")
        }
    }
}
