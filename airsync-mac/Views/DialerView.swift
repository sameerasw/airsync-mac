//
//  DialerView.swift
//  airsync-mac
//
//  Phone dialer to initiate calls from Mac
//

import SwiftUI

struct DialerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var phoneNumber = ""
    @State private var isDialing = false
    @FocusState private var isTextFieldFocused: Bool
    
    private let dialPadButtons: [[DialButton]] = [
        [.init(digit: "1", letters: ""), .init(digit: "2", letters: "ABC"), .init(digit: "3", letters: "DEF")],
        [.init(digit: "4", letters: "GHI"), .init(digit: "5", letters: "JKL"), .init(digit: "6", letters: "MNO")],
        [.init(digit: "7", letters: "PQRS"), .init(digit: "8", letters: "TUV"), .init(digit: "9", letters: "WXYZ")],
        [.init(digit: "*", letters: ""), .init(digit: "0", letters: "+"), .init(digit: "#", letters: "")]
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Dialer")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            // Phone number display with hidden text field for keyboard input
            ZStack {
                // Hidden text field to capture keyboard input
                TextField("", text: $phoneNumber)
                    .textFieldStyle(.plain)
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .focused($isTextFieldFocused)
                    .opacity(0.01) // Nearly invisible but still functional
                    .onChange(of: phoneNumber) { _, newValue in
                        // Filter to only allow valid phone characters
                        phoneNumber = newValue.filter { char in
                            char.isNumber || char == "+" || char == "*" || char == "#"
                        }
                    }
                
                // Visual display
                HStack {
                    Text(phoneNumber.isEmpty ? "Enter number" : formatPhoneNumber(phoneNumber))
                        .font(.system(size: 32, weight: .light, design: .rounded))
                        .foregroundColor(phoneNumber.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    Spacer()
                    
                    if !phoneNumber.isEmpty {
                        Button(action: { 
                            if !phoneNumber.isEmpty {
                                phoneNumber.removeLast()
                            }
                        }) {
                            Image(systemName: "delete.left.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onLongPressGesture {
                            phoneNumber = ""
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 60)
            .contentShape(Rectangle())
            .onTapGesture {
                isTextFieldFocused = true
            }
            
            // Dial pad
            VStack(spacing: 12) {
                ForEach(dialPadButtons, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row) { button in
                            DialPadButton(button: button) {
                                phoneNumber += button.digit
                            } onLongPress: {
                                if button.digit == "0" {
                                    phoneNumber += "+"
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Call button
            HStack(spacing: 20) {
                // Call button
                Button(action: initiateCall) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 70, height: 70)
                        
                        if isDialing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "phone.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(phoneNumber.isEmpty || isDialing)
                .opacity(phoneNumber.isEmpty ? 0.5 : 1)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.vertical)
        .frame(width: 320, height: 520)
        .onAppear {
            // Auto-focus the text field when dialer appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func formatPhoneNumber(_ number: String) -> String {
        // Simple formatting - just add spaces for readability
        let cleaned = number.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
        return cleaned
    }
    
    private func initiateCall() {
        guard !phoneNumber.isEmpty else { return }
        
        isDialing = true
        
        // Send dial command to Android
        WebSocketServer.shared.initiateCall(phoneNumber: phoneNumber)
        
        // Close dialer after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isDialing = false
            dismiss()
        }
    }
}

struct DialButton: Identifiable, Hashable {
    let id = UUID()
    let digit: String
    let letters: String
}

struct DialPadButton: View {
    let button: DialButton
    let action: () -> Void
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(button.digit)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                
                if !button.letters.isEmpty {
                    Text(button.letters)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .background(
                Circle()
                    .fill(isPressed ? Color.primary.opacity(0.2) : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress()
                }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = hovering
            }
        }
    }
}

// MARK: - New Message Composer
struct NewMessageView: View {
    @Environment(\.dismiss) var dismiss
    @State private var recipient = ""
    @State private var messageText = ""
    @State private var isSending = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("New Message")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Recipient field
            HStack {
                Text("To:")
                    .foregroundColor(.secondary)
                
                TextField("Phone number", text: $recipient)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            
            // Message field
            VStack(alignment: .leading) {
                TextEditor(text: $messageText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            
            // Character count
            HStack {
                Spacer()
                Text("\(messageText.count)/160")
                    .font(.caption)
                    .foregroundColor(messageText.count > 160 ? .orange : .secondary)
            }
            
            // Send button
            Button(action: sendMessage) {
                HStack {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text("Send")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSend ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            
            Spacer()
        }
        .padding()
        .frame(width: 350, height: 400)
    }
    
    private var canSend: Bool {
        !recipient.isEmpty && !messageText.isEmpty
    }
    
    private func sendMessage() {
        guard canSend else { return }
        
        isSending = true
        
        // Send SMS via WebSocket
        WebSocketServer.shared.sendSms(to: recipient, message: messageText)
        
        // Force refresh SMS threads after a delay to show the new message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Force refresh by requesting new data
            _ = LiveNotificationManager.shared.getSmsThreads(forceRefresh: true)
            isSending = false
            dismiss()
        }
    }
}
