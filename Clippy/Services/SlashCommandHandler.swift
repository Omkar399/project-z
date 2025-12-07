//
//  SlashCommandHandler.swift
//  ProjectZ
//
//  Handles instant slash commands (no Grok API calls)
//

import Foundation

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
                
                // Session memory
                let sessionSummary = self.conversationManager?.getSessionSummary() ?? "No session"
                let sessionCount = self.conversationManager?.getConversationCount() ?? 0
                
                // Fetch Mem0 memories asynchronously
                Task {
                    if let mem0Service = self.mem0Service {
                        let memories = await mem0Service.getAllMemories()
                        let formattedMemories = mem0Service.formatMemoriesForDisplay(memories)
                        
                        await MainActor.run {
                            let message = """
                            🧠 **Memory Status**
                            
                            **Session Memory:** \(sessionCount) turns
                            Status: \(sessionSummary)
                            
                            **Long-term Memory (Mem0):** \(memories.count) facts
                            \(memories.isEmpty ? "No long-term memories yet." : "\n\(formattedMemories)")
                            
                            Tip: Use /obliviate to clear session only
                            """
                            
                            // This is a workaround since we can't return async from Command action
                            print("💬 Memories: \(message)")
                        }
                    }
                }
                
                return CommandResult(
                    success: true,
                    message: "🔍 Fetching memories...",
                    shouldClearInput: false
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

