//
//  SettingsView.swift
//  yoink
//
//  Created by user on 25.01.2026.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            LogsSettingsView()
                .tabItem {
                    Text("Logs")
                }
        }
        .padding(20)
        .frame(width: 360, height: 160)
    }
}

private struct LogsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Open Log") {
                    NSWorkspace.shared.open(AppLogger.shared.logFileURL)
                }

                Button("Clear Log") {
                    AppLogger.shared.clearLog()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
