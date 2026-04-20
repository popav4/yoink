//
//  DownloadModels.swift
//  yoink
//

import SwiftUI

enum CookiesBrowser: String, CaseIterable {
    case none       = ""
    case firefox    = "firefox"
    case chrome     = "chrome"
    case chromium   = "chromium"
    case brave      = "brave"
    case opera      = "opera"
    case edge       = "edge"
    case safari     = "safari"
    case vivaldi    = "vivaldi"
    case whale      = "whale"

    var displayName: String {
        switch self {
        case .none:     return "None"
        case .firefox:  return "Firefox"
        case .chrome:   return "Chrome"
        case .chromium: return "Chromium"
        case .brave:    return "Brave"
        case .opera:    return "Opera"
        case .edge:     return "Edge"
        case .safari:   return "Safari"
        case .vivaldi:  return "Vivaldi"
        case .whale:    return "Whale"
        }
    }
}

enum DownloadMode: String, CaseIterable, Identifiable {
    case video
    case audio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video:
            return "Video"
        case .audio:
            return "Audio"
        }
    }
}

struct DownloadFormatOption: Identifiable, Hashable {
    let id: String
    let formatID: String?
    let container: String?
    let displayName: String

    static let bestVideo = DownloadFormatOption(
        id: "best-video",
        formatID: nil,
        container: nil,
        displayName: "Best available"
    )

    static let bestAudio = DownloadFormatOption(
        id: "best-audio",
        formatID: nil,
        container: "mp3",
        displayName: "Best available (mp3)"
    )
}

struct DownloadRequest {
    let url: String
    let mode: DownloadMode
    let selectedVideoFormat: DownloadFormatOption
    let selectedAudioFormat: DownloadFormatOption
    let customFileName: String?
    let ytDlpExecutablePathOverride: String?
    let cookiesBrowser: CookiesBrowser
    /// Optional profile path: passed as `browser:path` to yt-dlp `--cookies-from-browser`.
    let cookiesBrowserProfile: String?
}

struct DownloadItem: Identifiable {
    let id = UUID()
    let url: String
    let mode: DownloadMode
    var fileName: String?
    var status: DownloadStatus
    var statusReason: String?
    var progress: Double
    var speedText: String?
    var etaText: String?
    var fileSizeText: String?
    let addedText: String

    init(url: String, mode: DownloadMode, status: DownloadStatus, progress: Double) {
        self.url = url
        self.mode = mode
        self.fileName = nil
        self.status = status
        self.statusReason = nil
        self.progress = progress
        self.speedText = nil
        self.etaText = nil
        self.fileSizeText = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        self.addedText = formatter.string(from: Date())
    }
}

enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case skipped = "Skipped"
    case done = "Done"
    case failed = "Failed"

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .queued:
            return .secondary
        case .downloading:
            return .blue
        case .skipped:
            return .orange
        case .done:
            return .green
        case .failed:
            return .red
        }
    }
}

enum DownloadEngineEvent {
    case status(DownloadStatus)
    case destinationFileName(String)
    case progress(Double)
    case speed(String)
    case eta(String?)
    case fileSize(String)
    case finished(Int32, skipped: Bool, message: String?)
}
