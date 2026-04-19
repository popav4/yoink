//
//  ContentView.swift
//  yoink
//
//  Created by user on 20.01.2026.
//

import SwiftUI

struct ContentView: View {
    private enum FocusField: Hashable {
        case url
    }

    @StateObject private var viewModel = DownloadViewModel()
    @FocusState private var focusedField: FocusField?
    private static let downloadsMinHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Path to yt-dlp (optional override)", text: $viewModel.ytDlpExecutablePathText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.ytDlpExecutablePathText) { _, _ in
                                viewModel.onYtDlpPathChanged()
                            }

                        Button("Use Auto Detected") {
                            viewModel.useAutoDetectedYtDlpPath()
                        }
                    }

                    Text(viewModel.ytDlpPathStatusText)
                        .font(.caption)
                        .foregroundColor(viewModel.isYtDlpPathValid ? .secondary : .red)
                        .lineLimit(2)
                }
                .padding(6)
            }

            GroupBox("Download") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Enter URL", text: $viewModel.urlText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .url)
                        .onChange(of: viewModel.urlText) { _, _ in
                            viewModel.onURLChanged()
                        }
                        .onSubmit {
                            let trimmed = viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                viewModel.startDownload()
                            }
                        }

                    TextField("File name (optional)", text: $viewModel.fileNameText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                viewModel.startDownload()
                            }
                        }

                    Picker("Mode", selection: $viewModel.selectedMode) {
                        ForEach(DownloadMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Button("Analyze") {
                            viewModel.analyzeFormats()
                        }
                        .disabled(viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAnalyzing)

                        if viewModel.isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(viewModel.analysisStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if viewModel.selectedMode == .video {
                        if viewModel.availableVideoFormats.count > 1 || viewModel.availableAudioFormats.count > 1 {
                            HStack(spacing: 12) {
                                Text("Video format")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $viewModel.selectedVideoOptionID) {
                                    ForEach(viewModel.availableVideoFormats) { option in
                                        Text(option.displayName)
                                            .tag(option.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 420, alignment: .leading)
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 12) {
                                Text("Audio format")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $viewModel.selectedVideoAudioOptionID) {
                                    ForEach(viewModel.availableAudioFormats) { option in
                                        Text(option.displayName)
                                            .tag(option.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 360, alignment: .leading)
                                Spacer(minLength: 0)
                            }
                        } else {
                            Text("Video format: Best available, Audio format: Best available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if viewModel.availableAudioFormats.count > 1 {
                            HStack(spacing: 12) {
                                Text("Audio format")
                                    .frame(width: 110, alignment: .leading)
                                Picker("", selection: $viewModel.selectedAudioOnlyOptionID) {
                                    ForEach(viewModel.availableAudioFormats) { option in
                                        Text(option.displayName)
                                            .tag(option.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 360, alignment: .leading)
                                Spacer(minLength: 0)
                            }
                        } else {
                            Text("Audio format: Best available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .frame(minHeight: Self.downloadsMinHeight, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                } else {
                    ScrollView {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("URL").bold()
                                Text("File").bold()
                                Text("Type").bold()
                                Text("Status").bold()
                                Text("Progress").bold()
                                Text("Speed").bold()
                                Text("ETA").bold()
                                Text("Size").bold()
                                Text("Added").bold()
                            }
                            Divider()
                                .gridCellColumns(9)

                            ForEach(viewModel.downloads) { item in
                                GridRow {
                                    Text(item.url)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                                    Text(item.fileName ?? "Resolving...")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                                    Text(item.mode.displayName)
                                        .frame(width: 56, alignment: .leading)
                                    Text(item.status.displayName)
                                        .foregroundStyle(item.status.color)
                                        .frame(width: 80, alignment: .leading)
                                    Text("\(Int(item.progress * 100))%")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Text(item.speedText ?? "—")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 88, alignment: .leading)
                                    Text(item.etaText ?? "—")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Text(item.fileSizeText ?? "—")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 72, alignment: .leading)
                                    Text(item.addedText)
                                        .frame(width: 128, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Fill URL") {
                                        viewModel.urlText = item.url
                                    }
                                    if let fileName = item.fileName {
                                        Button("Fill File Name") {
                                            viewModel.fileNameText = fileName
                                        }
                                        Divider()
                                        Button("Fill URL and File Name") {
                                            viewModel.urlText = item.url
                                            viewModel.fileNameText = fileName
                                        }
                                    }
                                }

                                if let reason = item.statusReason,
                                   (item.status == .skipped || item.status == .failed),
                                   !reason.isEmpty {
                                    GridRow {
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundStyle(item.status.color)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .gridCellColumns(9)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: Self.downloadsMinHeight, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(minHeight: Self.downloadsMinHeight, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .url
            }
        }
    }

}

#Preview {
    ContentView()
}
