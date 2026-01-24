//
//  ModernMessagesView.swift
//  airsync-mac
//
//  Modern glassmorphic messages view
//

import SwiftUI

struct MessagesView: View {
    @ObservedObject private var manager = LiveNotificationManager.shared
    @State private var searchText = ""
    @State private var showNewMessage = false
    
    var filteredThreads: [SmsThread] {
        if searchText.isEmpty {
            return manager.smsThreads
        } else {
            return manager.smsThreads.filter { thread in
                thread.displayName.localizedCaseInsensitiveContains(searchText) ||
                thread.address.contains(searchText) ||
                thread.snippet.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search messages...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.background.opacity(0.5))
            
            Divider()
            
            // Messages List
            ScrollView {
                if filteredThreads.isEmpty {
                    if manager.smsThreads.isEmpty {
                        EmptyStateCard(
                            icon: "message.fill",
                            title: "No Messages",
                            message: "SMS conversations will appear here"
                        )
                        .padding()
                    } else {
                        // No search results
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No messages found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Try searching with a different term")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredThreads) { thread in
                            NavigationLink(destination: SmsDetailView(thread: thread)) {
                                MessageThreadRow(thread: thread, searchText: searchText)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showNewMessage = true }) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Message")
            }
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageView()
        }
        .onAppear {
            // Use caching - this will return cached data immediately and request fresh data if needed
            _ = manager.getSmsThreads()
        }
    }
}

struct MessageThreadRow: View {
    let thread: SmsThread
    let searchText: String
    @State private var isHovered = false
    
    init(thread: SmsThread, searchText: String = "") {
        self.thread = thread
        self.searchText = searchText
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 44, height: 44)
                
                Text(thread.displayName.prefix(1).uppercased())
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HighlightedText(
                        text: thread.displayName,
                        searchText: searchText,
                        font: .headline,
                        weight: thread.hasUnread ? .semibold : .regular
                    )
                    
                    Spacer()
                    
                    Text(thread.date, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    HighlightedText(
                        text: thread.snippet,
                        searchText: searchText,
                        font: .subheadline,
                        color: thread.hasUnread ? .primary : .secondary
                    )
                    .lineLimit(2)
                    
                    Spacer()
                    
                    // Read-only indicator or Unread badge
                    if isReadOnlyThread(thread) {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if thread.unreadCount > 0 {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                            
                            Text("\(thread.unreadCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            Group {
                if isHovered {
                    Color.primary.opacity(0.05)
                } else if thread.hasUnread {
                    Color.blue.opacity(0.05)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle()) // Make entire card clickable
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    // Helper function to determine if thread is read-only
    private func isReadOnlyThread(_ thread: SmsThread) -> Bool {
        let address = thread.address
        
        // Check for short codes (typically 5-6 digits)
        if address.count <= 6 && address.allSatisfy({ $0.isNumber }) {
            return true
        }
        
        // Check for common service prefixes
        let servicePrefixes = ["12345", "54321", "88888", "99999", "00000"]
        if servicePrefixes.contains(where: { address.hasPrefix($0) }) {
            return true
        }
        
        // Check for notification keywords in contact name or recent messages
        let notificationKeywords = ["noreply", "no-reply", "donotreply", "notification", "alert", "system", "automated"]
        let displayName = thread.displayName.lowercased()
        if notificationKeywords.contains(where: { displayName.contains($0) }) {
            return true
        }
        
        // Check recent messages for automated patterns
        let snippet = thread.snippet.lowercased()
        let automatedPatterns = ["do not reply", "automated message", "this is an automated", "unsubscribe"]
        if automatedPatterns.contains(where: { snippet.contains($0) }) {
            return true
        }
        
        return false
    }
}

// Helper view for highlighting search text
struct HighlightedText: View {
    let text: String
    let searchText: String
    let font: Font
    let weight: Font.Weight?
    let color: Color?
    
    init(text: String, searchText: String, font: Font, weight: Font.Weight? = nil, color: Color? = nil) {
        self.text = text
        self.searchText = searchText
        self.font = font
        self.weight = weight
        self.color = color
    }
    
    var body: some View {
        if searchText.isEmpty {
            Text(text)
                .font(font)
                .fontWeight(weight)
                .foregroundColor(color)
        } else {
            let parts = text.components(separatedBy: searchText)
            if parts.count > 1 {
                // Text contains search term
                HStack(spacing: 0) {
                    ForEach(0..<parts.count, id: \.self) { index in
                        Text(parts[index])
                            .font(font)
                            .fontWeight(weight)
                            .foregroundColor(color)
                        
                        if index < parts.count - 1 {
                            Text(searchText)
                                .font(font)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .background(Color.yellow.opacity(0.3))
                        }
                    }
                }
            } else {
                // Text doesn't contain search term
                Text(text)
                    .font(font)
                    .fontWeight(weight)
                    .foregroundColor(color)
            }
        }
    }
}
