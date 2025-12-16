//
//  SlashCommandHandler.swift
//  ProjectZ
//
//  Handles instant slash commands (no Grok API calls)
//

import Foundation
import Combine
import EventKit

class SlashCommandHandler {
    struct Command {
        let name: String
        let description: String
        let aliases: [String]
        let action: () -> CommandResult
    }
    
    struct CommandResult {
        let success: Bool
        let message: String
        let shouldClearInput: Bool
    }
    
    struct CommandSuggestion: Identifiable {
        let id = UUID()
        let command: String
        let description: String
    }
    
    // Dependencies (set externally)
    weak var conversationManager: ConversationManager?
    weak var guardianService: GuardianService?
    weak var mem0Service: Mem0Service?
    weak var calendarService: CalendarService?
    weak var grokService: GrokService?
    
    // Output for async command results
    let outputPublisher = PassthroughSubject<String, Never>()
    
    private var commands: [Command] = []
    
    init() {
        setupCommands()
    }
    
    // MARK: - Command Setup
    
    private func setupCommands() {
        commands = [
            Command(
                name: "obliviate",
                description: "Clear session memory (Mem0 memories persist)",
                aliases: ["clear", "forget"]
            ) { [weak self] in
                self?.conversationManager?.clearHistory(reason: "user command")
                return CommandResult(
                    success: true,
                    message: "🧹 Session memory cleared. Mem0 long-term memories still intact.",
                    shouldClearInput: true
                )
            },
            
            Command(
                name: "memories",
                description: "Show what ProjectZ remembers about you",
                aliases: ["memory", "remember"]
            ) { [weak self] in
                guard let self = self else {
                    return CommandResult(success: false, message: "Error: Handler not available", shouldClearInput: false)
                }
                
                // Fetch Mem0 memories asynchronously
                Task {
                    if let mem0Service = self.mem0Service {
                        let memories = await mem0Service.getAllMemories()
                        
                        await MainActor.run {
                            // Format memories as JSON cards
                            if memories.isEmpty {
                                // Show a single card indicating no memories
                                let noMemoriesJSON = """
                                [{
                                    "title": "No Memories Yet",
                                    "time": "Long-term",
                                    "summary": "Start having conversations with ProjectZ to build long-term memories. Your preferences, important information, and context will be remembered across sessions.",
                                    "points": ["💡 Tip: Use /obliviate to clear session memory only", "🧠 Long-term memories persist across sessions"]
                                }]
                                """
                                self.outputPublisher.send(noMemoriesJSON)
                            } else {
                                // Format each memory as a Briefing card
                                var briefings: [[String: Any]] = []
                                for (index, memory) in memories.enumerated() {
                                    var briefing: [String: Any] = [
                                        "title": "Memory \(index + 1)",
                                        "time": "Long-term",
                                        "summary": memory.memory,
                                        "points": []
                                    ]
                                    
                                    // Add score if available
                                    if let score = memory.score {
                                        briefing["time"] = "Relevance: \(String(format: "%.2f", score))"
                                    }
                                    
                                    briefings.append(briefing)
                                }
                                
                                // Convert to JSON
                                if let jsonData = try? JSONSerialization.data(withJSONObject: briefings, options: .prettyPrinted),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    self.outputPublisher.send(jsonString)
                                } else {
                                    // Fallback to text if JSON serialization fails
                                    let fallbackMessage = "🧠 Found \(memories.count) memories:\n\n" + mem0Service.formatMemoriesForDisplay(memories)
                                    self.outputPublisher.send(fallbackMessage)
                                }
                            }
                        }
                    } else {
                        await MainActor.run {
                            self.outputPublisher.send("⚠️ Mem0 service not available. Please check if the service is running.")
                        }
                    }
                }
                
                return CommandResult(
                    success: true,
                    message: "🔍 Fetching memories...",
                    shouldClearInput: true
                )
            },
            
            Command(
                name: "help",
                description: "Show all available commands",
                aliases: ["?", "commands"]
            ) { [weak self] in
                guard let self = self else {
                    return CommandResult(success: false, message: "Error", shouldClearInput: false)
                }
                
                var helpText = "⚡️ **Available Commands**\n\n"
                for cmd in self.commands {
                    helpText += "`/\(cmd.name)` - \(cmd.description)\n"
                    if !cmd.aliases.isEmpty {
                        helpText += "  *Aliases: \(cmd.aliases.map { "/\($0)" }.joined(separator: ", "))*\n"
                    }
                    helpText += "\n"
                }
                
                return CommandResult(
                    success: true,
                    message: helpText,
                    shouldClearInput: false
                )
            },
            
            Command(
                name: "guardian",
                description: "Toggle Guardian mode on/off",
                aliases: ["guard", "protect"]
            ) { [weak self] in
                guard let guardian = self?.guardianService else {
                    return CommandResult(
                        success: false,
                        message: "⚠️ Guardian service not available",
                        shouldClearInput: false
                    )
                }
                
                guardian.isEnabled.toggle()
                let status = guardian.isEnabled ? "enabled" : "disabled"
                let emoji = guardian.isEnabled ? "🛡️" : "💤"
                
                if guardian.isEnabled {
                    guardian.startMonitoring()
                } else {
                    guardian.stopMonitoring()
                }
                
                return CommandResult(
                    success: true,
                    message: "\(emoji) Guardian mode \(status)",
                    shouldClearInput: true
                )
            },
            
            Command(
                name: "meetnotes",
                description: "Prepare a briefing for upcoming meetings",
                aliases: ["meetings", "notes"]
            ) { [weak self] in
                guard let self = self else { return CommandResult(success: false, message: "Error", shouldClearInput: false) }
                
                Task {
                    guard let calendar = self.calendarService,
                          let mem0 = self.mem0Service,
                          let grok = self.grokService else {
                        print("⚠️ Services not available for /meetnotes")
                        return
                    }
                    
                    // 1. Fetch upcoming meetings
                    let events = await calendar.getNextEvents(limit: 3)
                    if events.isEmpty {
                        await MainActor.run { print("💬 No upcoming meetings found.") }
                        return
                    }
                    
                    var briefingContext = "Here are the upcoming meetings:\n\n"
                    
                    for (index, event) in events.enumerated() {
                        let title = event.title ?? "Untitled"
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d, h:mm a"
                        let time = formatter.string(from: event.startDate)
                        
                        briefingContext += "Event \(index + 1):\nTitle: \(title)\nTime: \(time)\n"
                        
                        // Enhanced Context Retrieval
                        // We search for the Title + Attendees to find relevant long-term memories
                        var searchTerms = title
                        if let attendees = event.attendees {
                             let attendeeNames = attendees.compactMap { $0.name }.joined(separator: " ")
                             if !attendeeNames.isEmpty {
                                 briefingContext += "Attendees: \(attendeeNames)\n"
                                 searchTerms += " " + attendeeNames
                             }
                        }
                        
                        // Also check notes for keywords? (Optional, might be too long)
                        // For now, Title + Attendees is a strong signal.
                        
                        let memories = await mem0.searchMemories(query: searchTerms, limit: 5)
                        if !memories.isEmpty {
                            briefingContext += "🧠 Related Memory: " + memories.map { $0.memory }.joined(separator: "; ") + "\n"
                        } else {
                            briefingContext += "🧠 No related memories found for query: '\(searchTerms)'\n"
                        }
                        briefingContext += "\n"
                    }
                    
                    briefingContext += """
                    
                    Task: Generate a briefing for these meetings.
                    output ONLY a JSON array with this structure (no markdown fields):
                    [
                        {
                            "title": "Meeting Title",
                            "time": "Date string",
                            "summary": "One sentence summary combining context",
                            "points": ["Key point 1", "Key point 2"]
                        }
                    ]
                    """
                    
                    // 3. Ask Grok for summary
                    let response = await grok.chat(message: briefingContext, context: nil)
                    
                    await MainActor.run {
                        // Send the raw JSON response
                        self.outputPublisher.send(response)
                    }
                }
                
                return CommandResult(
                    success: true,
                    message: "📅 Analyzing calendar and memories...",
                    shouldClearInput: true
                )
            }
        ]
    }
    
    // MARK: - Command Execution
    
    /// Check if input is a slash command
    func isCommand(_ input: String) -> Bool {
        return input.hasPrefix("/")
    }
    
    /// Execute a slash command
    func execute(_ input: String) -> CommandResult {
        // Remove the leading "/"
        let commandString = String(input.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
        
        // Empty command
        if commandString.isEmpty {
            return CommandResult(
                success: false,
                message: "Type / to see available commands",
                shouldClearInput: false
            )
        }
        
        // Find matching command
        for command in commands {
            if command.name == commandString || command.aliases.contains(commandString) {
                return command.action()
            }
        }
        
        // Unknown command
        return CommandResult(
            success: false,
            message: "❓ Unknown command: /\(commandString)\nType /help to see available commands",
            shouldClearInput: false
        )
    }
    
    // MARK: - Autocomplete
    
    /// Get command suggestions based on partial input
    func getSuggestions(for input: String) -> [CommandSuggestion] {
        guard input.hasPrefix("/") else { return [] }
        
        let query = String(input.dropFirst()).lowercased()
        
        // Empty query - show all commands
        if query.isEmpty {
            return commands.map { cmd in
                CommandSuggestion(command: "/\(cmd.name)", description: cmd.description)
            }
        }
        
        // Filter commands that match the query
        var suggestions: [CommandSuggestion] = []
        
        for command in commands {
            // Check if command name matches
            if command.name.hasPrefix(query) {
                suggestions.append(CommandSuggestion(
                    command: "/\(command.name)",
                    description: command.description
                ))
            }
            
            // Check if any alias matches
            for alias in command.aliases {
                if alias.hasPrefix(query) && !suggestions.contains(where: { $0.command == "/\(command.name)" }) {
                    suggestions.append(CommandSuggestion(
                        command: "/\(alias)",
                        description: "\(command.description) (alias for /\(command.name))"
                    ))
                }
            }
        }
        
        return suggestions
    }
}

