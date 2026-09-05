//
//  NotificationSummaryView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-06-05.
//

import SwiftUI
import FoundationModels
import Combine

struct SummaryLine: Identifiable {
    let id = UUID()
    let text: String
    let isHeader: Bool
}

class NotificationSummaryViewModel: ObservableObject {
    static let shared = NotificationSummaryViewModel()
    
    @Published var summaryText: String = ""
    @Published var isGeneratingSummary: Bool = false
    @Published var showSummary: Bool = false
    @Published var showMenubarSummary: Bool = false
    
    private var lastGeneratedTime: Date?
    private var lastNotificationsHash: String = ""
    
    func generateSummary(notifications: [Notification], androidApps: [String: AndroidApp], isFromToolbar: Bool = false) {
        let filtered = AppState.shared.includeSilentInAIOption ? notifications : notifications.filter { $0.priority != "silent" }
        guard !filtered.isEmpty else { return }
        
        if isFromToolbar {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showSummary.toggle()
            }
            if !showSummary {
                return
            }
        }
        
        let currentHash = filtered.map { "\($0.id)-\($0.title)-\($0.body)" }.joined(separator: "|")
        let now = Date()
        
        if let lastTime = lastGeneratedTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= 120.0 && currentHash != lastNotificationsHash {
                performGeneration(filtered: filtered, androidApps: androidApps, hash: currentHash, now: now)
            }
        } else {
            performGeneration(filtered: filtered, androidApps: androidApps, hash: currentHash, now: now)
        }
    }
    
    private func performGeneration(filtered: [Notification], androidApps: [String: AndroidApp], hash: String, now: Date) {
        isGeneratingSummary = true
        lastGeneratedTime = now
        lastNotificationsHash = hash
        
        var notificationsText = ""
        let grouped = Dictionary(grouping: filtered) { notif in
            androidApps[notif.package]?.name ?? "Android Device"
        }
        
        for (appName, notifs) in grouped {
            notificationsText += "\n[\(appName)]:\n"
            for notif in notifs {
                let title = notif.title
                let body = notif.body
                notificationsText += "- \(title): \(body)\n"
            }
        }
        
        let prompt = """
        Please provide a concise, high-level summary of the following notifications from my phone:
        \(notificationsText)
        Group them logically and highlight important alerts or action items.
        """
        
        Task {
            do {
                if #available(macOS 26.0, *) {
                    let session = LanguageModelSession(instructions: "You are an assistant that summarizes phone notifications. Write an extremely brief summary of active notifications. Group them by category using simple headers starting with '##' (e.g. '## Important Alerts') followed by brief lines. Do not mention specific app names. Never use conversational filler, keep it to 2-3 items max.")
                    let response = try await session.respond(to: prompt)
                    let cleaned = response.content.replacingOccurrences(of: "\r\n", with: "\n")
                    await animateWritingText(cleaned)
                } else {
                    await MainActor.run {
                        summaryText = "AI summaries require macOS 26.0 or later."
                    }
                }
            } catch {
                await MainActor.run {
                    summaryText = "Error generating response: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isGeneratingSummary = false
            }
        }
    }
    
    @MainActor
    private func animateWritingText(_ fullText: String) async {
        summaryText = ""
        let lines = fullText.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let suffix = index == lines.count - 1 ? "" : "\n"
            withAnimation(.easeOut(duration: 0.35)) {
                summaryText.append(line + suffix)
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay between lines
        }
    }
}

struct NotificationSummaryView: View {
    @ObservedObject var viewModel: NotificationSummaryViewModel
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text("Summary")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.showSummary = false
                        viewModel.summaryText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            }
            
            if viewModel.isGeneratingSummary && viewModel.summaryText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing notifications...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        let lines: [SummaryLine] = viewModel.summaryText.components(separatedBy: "\n")
                            .map { line -> SummaryLine in
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                if trimmed.hasPrefix("#") {
                                    let clean = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                                    return SummaryLine(text: clean, isHeader: true)
                                } else {
                                    let clean = trimmed
                                        .replacingOccurrences(of: "^[\\*\\-\\•]\\s*", with: "", options: .regularExpression)
                                        .replacingOccurrences(of: "\\*", with: "")
                                    return SummaryLine(text: clean, isHeader: false)
                                }
                            }
                            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        ForEach(lines) { line in
                            Text(LocalizedStringKey(line.isHeader ? "**\(line.text)**" : line.text))
                                .font(line.isHeader ? .body : .subheadline)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, line.isHeader ? 6 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(16)
        .applyGlassViewIfAvailable(cornerRadius: 20)
        .modifier(AIGlowModifier(isGenerating: viewModel.isGeneratingSummary, cornerRadius: 20))
        .onHover { hovering in
            isHovering = hovering
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct MenubarSummaryCardView: View {
    @ObservedObject var viewModel: NotificationSummaryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text("Summary")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
            }
            
            if viewModel.isGeneratingSummary && viewModel.summaryText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing notifications...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    let lines: [SummaryLine] = viewModel.summaryText.components(separatedBy: "\n")
                        .map { line -> SummaryLine in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("#") {
                                let clean = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                                return SummaryLine(text: clean, isHeader: true)
                            } else {
                                let clean = trimmed
                                    .replacingOccurrences(of: "^[\\*\\-\\•]\\s*", with: "", options: .regularExpression)
                                    .replacingOccurrences(of: "\\*", with: "")
                                    .trimmingCharacters(in: .whitespaces)
                                return SummaryLine(text: clean, isHeader: false)
                            }
                        }
                        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    ForEach(lines) { line in
                        Text(LocalizedStringKey(line.isHeader ? "**\(line.text)**" : line.text))
                            .font(.system(size: line.isHeader ? 11 : 10, weight: line.isHeader ? .bold : .regular))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, line.isHeader ? 4 : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AIGlowModifier: ViewModifier {
    let isGenerating: Bool
    let cornerRadius: CGFloat
    
    @State private var gradientStops: [Gradient.Stop] = AIGlowModifier.generateGradientStops()
    @State private var timer: AnyCancellable?
    @State private var glowOpacity: Double = 0.15
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(stops: gradientStops),
                                center: .center
                            ),
                            lineWidth: isGenerating ? 2.5 : 1.5
                        )
                        .opacity(glowOpacity)
                    
                    if isGenerating {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(stops: gradientStops),
                                    center: .center
                                ),
                                lineWidth: 6.0
                            )
                            .blur(radius: 4.0)
                            .opacity(glowOpacity)
                            .compositingGroup()

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(stops: gradientStops),
                                    center: .center
                                ),
                                lineWidth: 10.0
                            )
                            .blur(radius: 8.0)
                            .opacity(glowOpacity * 0.7)
                            .compositingGroup()
                            
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(stops: gradientStops),
                                    center: .center
                                ),
                                lineWidth: 14.0
                            )
                            .blur(radius: 12.0)
                            .opacity(glowOpacity * 0.4)
                            .compositingGroup()
                    }
                }
            )
            .onAppear {
                updateGlowState(isGenerating: isGenerating)
            }
            .onChange(of: isGenerating) { _, newValue in
                updateGlowState(isGenerating: newValue)
            }
            .onDisappear {
                timer?.cancel()
                timer = nil
            }
    }
    
    private func updateGlowState(isGenerating: Bool) {
        if isGenerating {
            timer = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientStops = AIGlowModifier.generateGradientStops()
                    }
                }
            
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowOpacity = 0.8
            }
        } else {
            timer?.cancel()
            timer = nil
            withAnimation(.easeOut(duration: 2.0)) {
                glowOpacity = 0.4
            }
        }
    }
    
    static func generateGradientStops() -> [Gradient.Stop] {
        [
            Gradient.Stop(color: Color(hex: "BC82F3"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "F5B9EA"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "8D9FFF"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FF6778"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FFBA71"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "C686FF"), location: Double.random(in: 0...1))
        ].sorted { $0.location < $1.location }
    }
}

fileprivate extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)
        
        let r = Double((hexNumber & 0xff0000) >> 16) / 255
        let g = Double((hexNumber & 0x00ff00) >> 8) / 255
        let b = Double(hexNumber & 0x0000ff) / 255
        
        self.init(red: r, green: g, blue: b)
    }
}
