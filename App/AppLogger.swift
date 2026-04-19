//
//  AppLogger.swift
//  yoink
//
//  Created by user on 25.01.2026.
//

import Foundation

final class AppLogger {
    static let shared = AppLogger()
    static let loggingEnabledKey = "loggingEnabled"

    private let queue = DispatchQueue(label: "yoink.logger")
    private let formatter = ISO8601DateFormatter()
    private let logURL: URL

    private init() {
        let fileManager = FileManager.default
        let logsDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
        let baseDir = logsDir ?? fileManager.temporaryDirectory
        let folder = baseDir.appendingPathComponent("yoink", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        logURL = folder.appendingPathComponent("yoink.log")
    }

    var isLoggingEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.loggingEnabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.loggingEnabledKey)
        }
    }

    func log(_ message: String) {
        guard isLoggingEnabled else { return }
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"
        queue.async { [logURL] in
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: logURL, options: .atomic)
                }
            }
        }
    }

    var logFileURL: URL {
        logURL
    }

    func clearLog() {
        queue.async { [logURL] in
            try? FileManager.default.removeItem(at: logURL)
        }
    }
}
