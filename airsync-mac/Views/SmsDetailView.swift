//
//  SmsDetailView.swift
//  airsync-mac
//
//  SMS conversation detail view with chat interface
//

import SwiftUI

struct SmsDetailView: View {
    let thread: SmsThread
    @ObservedObject private var manager = LiveNotificationManager.shared
    @State private var messages: [SmsMessage] = []
    @State private var newMessage = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    // Computed property to determine if messages can be sent
    private var canSendMessages: Bool {
        !isReadOnlyConversation
    }
    
    // Determine if this conversation supports sending messages
    private var isReadOnlyConversation: Bool {
        // Common patterns for read-only conversations:
        // 1. Short codes (5-6 digits)
        // 2. Service numbers (starting with specific patterns)
        // 3. Notification-only senders
        
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Messages List
            messagesView
            
            // Input Area (if sending is supported) or Read-only indicator
            Divider()
            if canSendMessages {
                inputView
            } else {
                readOnlyIndicator
            }
        }
        .onAppear {
            loadMessages()
        }
        .navigationTitle("")
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Back Button
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Back to messages")
            
            // Contact Avatar
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                
                Text(thread.displayName.prefix(1).uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Contact Info
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(thread.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Message Count
            Text("\(messages.count) messages")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Refresh Button
            Button(action: loadMessages) {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
            }
            .buttonStyle(.plain)
            .help("Refresh messages")
        }
        .padding()
        .background(.background.opacity(0.5))
    }
    
    // MARK: - Messages View
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoading && messages.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading messages...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if messages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No messages in this conversation")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, thread: thread)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
            }
            .onChange(of: messages.count) { _, _ in
                // Auto-scroll to bottom when new messages arrive
                if let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input View
    
    private var inputView: some View {
        HStack(spacing: 12) {
            // Text Input
            TextField("Type a message...", text: $newMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit {
                    sendMessage()
                }
            
            // Send Button
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.background.opacity(0.5))
    }
    
    // MARK: - Read-Only Indicator
    
    private var readOnlyIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Read-Only Conversation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("This conversation doesn't support replies")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(.background.opacity(0.3))
    }
    
    // MARK: - Helper Methods
    
    private func loadMessages() {
        isLoading = true
        print("[sms-detail] Loading messages for thread: \(thread.threadId)")
        
        // Load existing messages from manager
        messages = manager.smsMessagesByThread[thread.threadId] ?? []
        
        // Request fresh messages for this thread
        WebSocketServer.shared.requestSmsMessages(threadId: thread.threadId, limit: 100)
        
        // Stop loading after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isLoading = false
            // Update with any new messages received
            messages = manager.smsMessagesByThread[thread.threadId] ?? messages
        }
    }
    
    private func sendMessage() {
        let messageText = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        
        print("[sms-detail] Sending message to \(thread.address): \(messageText)")
        
        // Send via WebSocket
        WebSocketServer.shared.sendSms(to: thread.address, message: messageText)
        
        // Clear input
        newMessage = ""
        
        // Optimistically add to local messages (will be replaced by real message from server)
        let optimisticMessage = SmsMessage(
            id: UUID().uuidString,
            threadId: thread.threadId,
            address: thread.address,
            body: messageText,
            date: Date(),
            type: 2, // sent
            read: true,
            contactName: thread.contactName
        )
        
        messages.append(optimisticMessage)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: SmsMessage
    let thread: SmsThread
    
    var body: some View {
        HStack {
            if message.isSent {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isSent ? .trailing : .leading, spacing: 4) {
                // Message Content
                Text(message.body)
                    .font(.body)
                    .foregroundColor(message.isSent ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        message.isSent 
                        ? Color.blue
                        : Color.gray.opacity(0.2)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )
                
                // Timestamp
                Text(message.date, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if message.isReceived {
                Spacer(minLength: 60)
            }
        }
    }
}
