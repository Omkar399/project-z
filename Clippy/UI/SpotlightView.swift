import SwiftUI
import SwiftData

struct SpotlightView: View {
    @EnvironmentObject var container: AppDependencyContainer
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var allItems: [Item]
    
    @State private var query: String = ""
    @State private var response: String = ""
    @State private var isProcessing: Bool = false
    @State private var isVisible: Bool = false
    @State private var debugLog: [String] = []
    @FocusState private var isInputFocused: Bool
    
    // Guardian mode
    @State private var isNudgeMode: Bool = false
    @State private var nudgeMessage: String = ""
    
    // Slash commands
    @State private var showCommandSuggestions: Bool = false
    @State private var commandSuggestions: [SlashCommandHandler.CommandSuggestion] = []
    
    private var inputFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isProcessing ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var commandSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commandSuggestions) { suggestion in
                Button(action: {
                    query = suggestion.command
                    showCommandSuggestions = false
                    handleQuery()
                }) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(suggestion.command)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                        
                        Text(suggestion.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.secondary.opacity(0.05))
                
                if suggestion.id != commandSuggestions.last?.id {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Input field
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .opacity(isProcessing ? 0.5 : 1.0)
                    .scaleEffect(isProcessing ? 0.8 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isProcessing)
                
                TextField("Ask anything...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isInputFocused)
                    .onSubmit {
                        handleQuery()
                    }
                    .onChange(of: query) { newValue in
                        updateCommandSuggestions(for: newValue)
                    }
                    .disabled(isProcessing)
                
                if !query.isEmpty {
                    Button(action: clearQuery) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .opacity(0.6)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(inputFieldBackground)
            
            // Slash Command Autocomplete
            if showCommandSuggestions && !commandSuggestions.isEmpty {
                commandSuggestionsView
            }
            
            // Guardian Nudge - appears when a guarded contact is detected
            if isNudgeMode {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                        Text("GUARDIAN MODE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    
                    Text(nudgeMessage)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Button("I understand") {
                            dismissNudge()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        Spacer()
                        
                        Text("Press Esc to close")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 2)
                        )
                )
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Response area - scrollable for long responses
            if !response.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        Text(response)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(16)
                    }
                    .frame(minHeight: 80, maxHeight: 400)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .padding(.top, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .id(response.count) // Force refresh when response changes
            }
            
            // Debug log area - always visible
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DEBUG LOG")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    Spacer()
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if debugLog.isEmpty {
                                Text("Waiting for query...")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.gray)
                            } else {
                                ForEach(Array(debugLog.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(log.contains("❌") ? .red : log.contains("✅") ? .green : .white)
                                        .id(index)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: debugLog.count) { oldValue, newValue in
                        if newValue > 0 {
                            proxy.scrollTo(newValue - 1, anchor: .bottom)
                        }
                    }
                }
                .frame(height: 150)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.top, 12)
            
        }
        .padding(20)
        .frame(width: 600)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: response)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 40, x: 0, y: 20)
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = true
            }
            // Focus the input field with multiple attempts
            isInputFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
                print("🎯 [SpotlightView] Focus requested")
            }
            
            // Listen for Guardian nudges
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowGuardianNudge"),
                object: nil,
                queue: .main
            ) { notification in
                if let message = notification.userInfo?["message"] as? String {
                    showNudge(message: message)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleQuery() {
        guard !query.isEmpty, !isProcessing else { return }
        
        let userQuery = query
        
        // Check if it's a slash command
        if userQuery.hasPrefix("/") {
            let slashHandler = container.slashCommandHandler
            let result = slashHandler.execute(userQuery)
            
            // Show result
            response = result.message
            
            // Clear input if requested
            if result.shouldClearInput {
                query = ""
            }
            
            // Hide suggestions
            showCommandSuggestions = false
            
            return
        }
        
        // Clear query but DON'T clear response yet (keep previous answer visible)
        query = ""
        isProcessing = true
        
        Task {
            await performQuery(userQuery)
        }
    }
    
    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logEntry = "[\(timestamp)] \(message)"
        print(logEntry)
        Task { @MainActor in
            debugLog.append(logEntry)
            // Keep only last 10 entries
            if debugLog.count > 10 {
                debugLog.removeFirst()
            }
        }
    }
    
    private func performQuery(_ userQuery: String) async {
        await MainActor.run { debugLog = [] }
        log("🔍 Starting query: \(userQuery)")
        
        // Perform vector search on clipboard history
        var clipboardContext: [RAGContextItem] = []
        
        // Search using the vector database
        log("🔍 Searching clipboard...")
        let searchResults = await container.clippy.search(query: userQuery, limit: 5)
        let vectorIds = Set(searchResults.map { $0.0 })
        log("🔍 Found \(vectorIds.count) vectors")
        
        if !vectorIds.isEmpty {
            // Filter items matching the search results
            let relevantItems = allItems.filter { item in
                guard let itemVectorId = item.vectorId else { return false }
                return vectorIds.contains(itemVectorId)
            }
            
            clipboardContext = relevantItems.map { item in
                RAGContextItem(
                    content: item.content,
                    tags: item.tags,
                    type: item.contentType,
                    timestamp: item.timestamp,
                    title: item.title
                )
            }
            log("🔍 Context: \(clipboardContext.count) items")
        }
        
        // Search Mem0 for long-term memories
        log("🧠 Searching Mem0 for relevant memories...")
        var mem0Memories: [Mem0Service.Memory] = []
        if container.mem0Service.isAvailable {
            mem0Memories = await container.mem0Service.searchMemories(query: userQuery, limit: 3)
            log("🧠 Found \(mem0Memories.count) Mem0 memories")
        } else {
            log("⚠️ Mem0 service not available")
        }
        
        // Send to Grok with agentic RAG + conversation history + Mem0 memories
        log("🤖 Calling Grok API...")
        let conversationHistory = container.conversationManager.getFormattedHistory()
        log("💬 Session history: \(conversationHistory.count) messages")
        
        // For now, we'll pass Mem0 memories as part of the clipboard context
        // TODO: Create a dedicated parameter for long-term memories
        let answer = await container.grokService.generateAnswer(
            question: userQuery,
            clipboardContext: clipboardContext,
            appName: container.clipboardMonitor.currentAppName,
            conversationHistory: conversationHistory
        )
        
        if let answer = answer {
            log("✅ Got response (\(answer.count) chars): \(answer.prefix(100))")
        } else {
            log("❌ Response is nil")
        }
        
        // CRITICAL: Update on MainActor in a single transaction
        await MainActor.run {
            // Set isProcessing false FIRST
            isProcessing = false
            
            // Then update response
            if let answer = answer, !answer.isEmpty {
                response = answer
                log("✅ Response displayed!")
                
                // Save to conversation history (session memory)
                container.conversationManager.addMessage(role: "user", content: userQuery)
                container.conversationManager.addMessage(role: "assistant", content: answer)
                log("💬 Saved to session history")
                
                // Save to Mem0 (long-term memory) - extract facts
                if container.mem0Service.isAvailable {
                    Task {
                        let messages = [(role: "user", content: userQuery), (role: "assistant", content: answer)]
                        let success = await container.mem0Service.addMemory(messages: messages)
                        if success {
                            log("🧠 Saved to Mem0 long-term memory")
                        } else {
                            log("⚠️ Failed to save to Mem0")
                        }
                    }
                }
            } else {
                let error = container.grokService.lastErrorMessage ?? "No response from Grok"
                response = "Error: \(error)"
                log("❌ Error: \(error)")
            }
            
            log("📊 isProcessing=\(isProcessing), response.count=\(response.count)")
        }
    }
    
    private func clearQuery() {
        withAnimation(.easeOut(duration: 0.2)) {
            query = ""
        }
    }
    
    // MARK: - Guardian Mode
    
    private func showNudge(message: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            nudgeMessage = message
            isNudgeMode = true
        }
        print("🛡️ [SpotlightView] Showing nudge: \(message)")
    }
    
    private func dismissNudge() {
        withAnimation(.easeOut(duration: 0.2)) {
            isNudgeMode = false
        }
        // Reset Guardian so it can warn again if user comes back to this contact
        container.guardianService.resetLastWarnedContact()
        print("🛡️ [SpotlightView] Nudge dismissed")
    }
    
    // MARK: - Slash Commands
    
    private func updateCommandSuggestions(for input: String) {
        if input.hasPrefix("/") {
            let suggestions = container.slashCommandHandler.getSuggestions(for: input)
            withAnimation(.easeInOut(duration: 0.15)) {
                commandSuggestions = suggestions
                showCommandSuggestions = !suggestions.isEmpty
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCommandSuggestions = false
                commandSuggestions = []
            }
        }
    }
}

// MARK: - Keyboard Hint Component

struct KeyboardHint: View {
    let key: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                )
            Text(label)
        }
    }
}

// Preview
#Preview {
    SpotlightView()
        .environmentObject(AppDependencyContainer())
        .frame(width: 640, height: 200)
        .background(Color.black.opacity(0.3))
}

