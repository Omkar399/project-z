//
//  ConversationManager.swift
//  Clippy
//
//  Manages conversation history for session continuity
//

import Foundation
import Combine

class ConversationManager: ObservableObject {
    struct Message: Codable, Identifiable {
        let id: UUID
        let role: String  // "user" or "assistant"
        let content: String
        let timestamp: Date
        
        init(role: String, content: String) {
            self.id = UUID()
            self.role = role
            self.content = content
            self.timestamp = Date()
        }
    }
    
    @Published var history: [Message] = []
    private var lastInteraction = Date()
    
    // Configuration
    private let sessionTimeout: TimeInterval = 30 * 60  // 30 minutes
    private let maxTurns = 20  // Keep last 20 conversation turns (40 messages total: user + assistant)
    
    init() {
        print("💬 [ConversationManager] Initialized")
    }
    
    // MARK: - Session Management
    
    /// Add a message to the conversation history
    func addMessage(role: String, content: String) {
        // Check if session has timed out
        if shouldStartNewSession() {
            clearHistory(reason: "session timeout")
        }
        
        let message = Message(role: role, content: content)
        history.append(message)
        lastInteraction = Date()
        
        // Truncate if too many messages
        truncateIfNeeded()
        
        print("💬 [ConversationManager] Added \(role) message. History: \(history.count) messages")
    }
    
    /// Get conversation history formatted for API calls
    func getFormattedHistory() -> [(role: String, content: String)] {
        return history.map { ($0.role, $0.content) }
    }
    
    /// Get conversation history as Message objects
    func getHistory() -> [Message] {
        return history
    }
    
    /// Clear all conversation history
    func clearHistory(reason: String = "manual") {
        let count = history.count
        history.removeAll()
        lastInteraction = Date()
        print("💬 [ConversationManager] Cleared history (\(count) messages removed) - Reason: \(reason)")
    }
    
    /// Check if we should start a new session
    private func shouldStartNewSession() -> Bool {
        let timeSinceLastInteraction = Date().timeIntervalSince(lastInteraction)
        return timeSinceLastInteraction > sessionTimeout && !history.isEmpty
    }
    
    /// Truncate old messages if exceeding max turns
    private func truncateIfNeeded() {
        let maxMessages = maxTurns * 2  // Each turn has user + assistant message
        if history.count > maxMessages {
            let messagesToRemove = history.count - maxMessages
            history.removeFirst(messagesToRemove)
            print("💬 [ConversationManager] Truncated \(messagesToRemove) old messages")
        }
    }
    
    // MARK: - Statistics
    
    func getConversationCount() -> Int {
        return history.count / 2  // Approximate number of turns
    }
    
    func getSessionAge() -> TimeInterval {
        guard !history.isEmpty else { return 0 }
        return Date().timeIntervalSince(lastInteraction)
    }
    
    func getSessionSummary() -> String {
        let turns = getConversationCount()
        let age = Int(getSessionAge() / 60)  // in minutes
        
        if history.isEmpty {
            return "No active session"
        }
        
        return "\(turns) turns, \(age)m ago"
    }
}

