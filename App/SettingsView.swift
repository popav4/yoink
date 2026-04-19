//
//  SettingsView.swift
//  yoink
//
//  Created by user on 25.01.2026.
//

import AppKit
import SwiftUI

private enum SettingsStorageInfo {
    static let defaultDownloadDirectoryKey = "defaultDownloadDirectory"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "io.github.popav4.yoink"
    }

    static var preferencesFileURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return libraryURL
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).plist", isDirectory: false)
    }

    static var preferencesDirectoryURL: URL {
        preferencesFileURL.deletingLastPathComponent()
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            DownloadsSettingsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }

            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }

            LogsSettingsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}

private struct DownloadsSettingsView: View {
    @AppStorage("defaultDownloadDirectory")
    private var defaultDownloadDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()

    @AppStorage("cookiesBrowser")
    private var cookiesBrowserRaw = CookiesBrowser.none.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default download folder")
                .font(.headline)

            Text(defaultDownloadDirectory)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button("Choose Folder...") {
                    chooseFolder()
                }

                Button("Reset to Downloads") {
                    defaultDownloadDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
                    AppLogger.shared.log("Default download directory reset: \(defaultDownloadDirectory)")
                }
            }

            Divider()

            Text("Cookies")
                .font(.headline)

            HStack(spacing: 12) {
                Text("Extract cookies from browser")
                Picker("", selection: $cookiesBrowserRaw) {
                    ForEach(CookiesBrowser.allCases, id: \.rawValue) { browser in
                        Text(browser.displayName).tag(browser.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Text("Used for sites that require login.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.directoryURL = URL(fileURLWithPath: defaultDownloadDirectory, isDirectory: true)

        if panel.runModal() == .OK, let selectedURL = panel.url {
            defaultDownloadDirectory = selectedURL.path
            AppLogger.shared.log("Default download directory updated: \(selectedURL.path)")
        }
    }
}

private struct StorageSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings storage")
                .font(.headline)

            Text("UserDefaults key: \(SettingsStorageInfo.defaultDownloadDirectoryKey)")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)

            Text(SettingsStorageInfo.preferencesFileURL.path)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button("Open Settings File") {
                    let fileURL = SettingsStorageInfo.preferencesFileURL
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        NSWorkspace.shared.open(fileURL)
                    } else {
                        NSWorkspace.shared.open(SettingsStorageInfo.preferencesDirectoryURL)
                    }
                }

                Button("Open Settings Folder") {
                    NSWorkspace.shared.open(SettingsStorageInfo.preferencesDirectoryURL)
                }
            }

            Spacer()
        }
    }
}

private struct LogsSettingsView: View {
    @AppStorage(AppLogger.loggingEnabledKey)
    private var isLoggingEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable logging", isOn: $isLoggingEnabled)

            Text("Current log file")
                .font(.headline)

            Text(AppLogger.shared.logFileURL.path)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button("Open Log") {
                    NSWorkspace.shared.open(AppLogger.shared.logFileURL)
                }
                .disabled(!isLoggingEnabled)

                Button("Open Log Folder") {
                    NSWorkspace.shared.open(AppLogger.shared.logFileURL.deletingLastPathComponent())
                }
                .disabled(!isLoggingEnabled)

                Button("Clear Log") {
                    AppLogger.shared.clearLog()
                }
                .disabled(!isLoggingEnabled)
            }

            Spacer()
        }
    }
}

#Preview {
    SettingsView()
}
