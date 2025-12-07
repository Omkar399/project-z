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
    @State private var showDebugLog: Bool = false
    @FocusState private var isInputFocused: Bool
    
    // Guardian mode
    @State private var isNudgeMode: Bool = false
    @State private var nudgeMessage: String = ""
    
    // Slash commands
    @State private var showCommandSuggestions: Bool = false
    @State private var commandSuggestions: [SlashCommandHandler.CommandSuggestion] = []
    
    // Theme
    private let gradient = LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    private var inputFieldBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: isProcessing ? [.blue, .purple] : [.white.opacity(0.2), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isProcessing ? 1.5 : 1
                    )
            )
            .shadow(color: isProcessing ? .blue.opacity(0.2) : .clear, radius: 10, x: 0, y: 0)
    }
    
    private var commandSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commandSuggestions) { suggestion in
                Button(action: {
                    query = suggestion.command
                    showCommandSuggestions = false
                    handleQuery()
                }) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        Text(suggestion.command)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Text(suggestion.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.turn.down.left")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    Rectangle()
                        .fill(Color.primary.opacity(0.03))
                        .opacity(suggestion.id == commandSuggestions.first?.id ? 1 : 0) // Highlight first? No selection state yet
                )
                
                if suggestion.id != commandSuggestions.last?.id {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Input Area
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: isProcessing ? "sparkles" : "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(gradient)
                        .symbolEffect(.bounce, value: isProcessing)
                }
                
                // Text Field
                TextField("Ask anything...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .light))
                    .focused($isInputFocused)
                    .onSubmit {
                        handleQuery()
                    }
                    .onChange(of: query) { newValue in
                        updateCommandSuggestions(for: newValue)
                    }
                    .disabled(isProcessing)
                
                // Trailing actions
                HStack(spacing: 8) {
                    if !query.isEmpty {
                        Button(action: clearQuery) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .opacity(0.6)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Debug toggle (subtle)
                    Button(action: { withAnimation { showDebugLog.toggle() } }) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 12))
                            .foregroundColor(showDebugLog ? .orange : .secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Debug Log")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(inputFieldBackground)
            
            // MARK: - Suggestions
            if showCommandSuggestions && !commandSuggestions.isEmpty {
                commandSuggestionsView
            }
            
            // MARK: - Guardian Mode
            if isNudgeMode {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .symbolEffect(.pulse)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GUARDIAN MODE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .tracking(1)
                            
                            Text("Protected Contact Detected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text(nudgeMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 38)
                    
                    HStack {
                        Spacer()
                        Button("Dismiss") {
                            dismissNudge()
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        
                        Button("I understand") {
                            dismissNudge()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.orange.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // MARK: - Response Area
            if !response.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Measuring content size with background GeometryReader if needed, 
                    // or just letting ScrollView expand naturally within limits.
                    // For dynamic resizing, we notify the controller of the content height.
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        HStack {
                            Image(systemName: "text.bubble.fill")
                                .foregroundStyle(gradient)
                            Text("Answer")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)
                        
                        // Content
                        Text(response)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.primary)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ViewHeightKey.self, value: geometry.size.height)
                    })
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom).combined(with: .scale(scale: 0.98))))
                .id(response.count) // Force refresh when response changes
            }
            
            // MARK: - Debug Log
            if showDebugLog {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("DEBUG LOG")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                if debugLog.isEmpty {
                                    Text("Waiting for query...")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.5))
                                } else {
                                    ForEach(Array(debugLog.enumerated()), id: \.offset) { index, log in
                                        Text(log)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(log.contains("❌") ? .red : log.contains("✅") ? .green : .secondary)
                                            .id(index)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: debugLog.count) { oldValue, newValue in
                            if newValue > 0 {
                                withAnimation {
                                    proxy.scrollTo(newValue - 1, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.5))
                )
                .padding(.top, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(24)
        .frame(width: 680) // Fixed width
        .background(
            ZStack {
                // Main frosted glass background
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 50, x: 0, y: 20)
                
                // Subtle gradient glow
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .clear, .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .onPreferenceChange(ViewHeightKey.self) { height in
            // Send height update to controller
            updateWindowHeight(contentHeight: height)
        }
        // Ensure window is transparent
        .onAppear {
            isVisible = true
            isInputFocused = true
            
            // Force focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
            
            // Guardian observer
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
        .scaleEffect(isVisible ? 1.0 : 0.96)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: response)
    }
    
    // MARK: - Actions
    
    private func updateWindowHeight(contentHeight: CGFloat) {
        // Base height (input + padding) roughly calculated or fixed minimum
        let baseHeight: CGFloat = 120 // Approximation of input area + padding
        let totalHeight = baseHeight + contentHeight + 40 // + extra padding
        
        // Notify controller via NotificationCenter for decoupling
        NotificationCenter.default.post(
            name: NSNotification.Name("SpotlightHeightChanged"),
            object: nil,
            userInfo: ["height": totalHeight]
        )
    }
    
    private func handleQuery() {
        guard !query.isEmpty, !isProcessing else { return }
        
        let userQuery = query
        
        // Slash Command Check
        if userQuery.hasPrefix("/") {
            let slashHandler = container.slashCommandHandler
            let result = slashHandler.execute(userQuery)
            
            withAnimation {
                response = result.message
                showCommandSuggestions = false
                if result.shouldClearInput {
                    query = ""
                }
            }
            return
        }
        
        query = ""
        withAnimation { isProcessing = true }
        
        Task {
            await performQuery(userQuery)
        }
    }
    
    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logEntry = "[\(timestamp)] \(message)"
        print(logEntry)
        Task { @MainActor in
            withAnimation {
                debugLog.append(logEntry)
                if debugLog.count > 20 { debugLog.removeFirst() }
            }
        }
    }
    
    private func performQuery(_ userQuery: String) async {
        await MainActor.run { debugLog = [] }
        log("🔍 Starting query: \(userQuery)")
        
        var clipboardContext: [RAGContextItem] = []
        
        // Search
        log("🔍 Searching clipboard...")
        let searchResults = await container.clippy.search(query: userQuery, limit: 5)
        let vectorIds = Set(searchResults.map { $0.0 })
        
        if !vectorIds.isEmpty {
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
        }
        
        // Mem0
        if container.mem0Service.isAvailable {
            _ = await container.mem0Service.searchMemories(query: userQuery, limit: 3)
            log("🧠 Mem0 search complete")
        }
        
        // Grok Generation
        log("🤖 Asking AI...")
        let conversationHistory = container.conversationManager.getFormattedHistory()
        
        let answer = await container.grokService.generateAnswer(
            question: userQuery,
            clipboardContext: clipboardContext,
            appName: container.clipboardMonitor.currentAppName,
            conversationHistory: conversationHistory
        )
        
        await MainActor.run {
            isProcessing = false
            
            if let answer = answer, !answer.isEmpty {
                response = answer
                
                // Save history
                container.conversationManager.addMessage(role: "user", content: userQuery)
                container.conversationManager.addMessage(role: "assistant", content: answer)
                
                // Save to Mem0
                if container.mem0Service.isAvailable {
                    Task {
                        let messages = [(role: "user", content: userQuery), (role: "assistant", content: answer)]
                        _ = await container.mem0Service.addMemory(messages: messages)
                    }
                }
            } else {
                let error = container.grokService.lastErrorMessage ?? "No response"
                response = "Could not generate an answer. \(error)"
            }
        }
    }
    
    private func clearQuery() {
        query = ""
    }
    
    // MARK: - Guardian Helpers
    
    private func showNudge(message: String) {
        withAnimation {
            nudgeMessage = message
            isNudgeMode = true
        }
    }
    
    private func dismissNudge() {
        withAnimation {
            isNudgeMode = false
        }
        container.guardianService.resetLastWarnedContact()
    }
    
    private func updateCommandSuggestions(for input: String) {
        if input.hasPrefix("/") {
            let suggestions = container.slashCommandHandler.getSuggestions(for: input)
            withAnimation {
                commandSuggestions = suggestions
                showCommandSuggestions = !suggestions.isEmpty
            }
        } else {
            withAnimation {
                showCommandSuggestions = false
            }
        }
    }
}

// Preference Key for Height
struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
