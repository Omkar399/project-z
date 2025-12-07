import SwiftUI
import SwiftData
import Combine

struct SpotlightView: View {
    @EnvironmentObject var container: AppDependencyContainer
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var allItems: [Item]
    
    @State private var query: String = ""
    @State private var response: String = ""
    @State private var briefings: [Briefing] = [] // For card UI
    
    struct Briefing: Identifiable, Codable {
        let id = UUID()
        let title: String
        let time: String
        let summary: String
        let points: [String]
        
        enum CodingKeys: String, CodingKey {
            case title, time, summary, points
        }
    }
    @State private var isProcessing: Bool = false
    @State private var isVisible: Bool = false
    @FocusState private var isInputFocused: Bool
    
    // Guardian mode
    @State private var isNudgeMode: Bool = false
    @State private var nudgeMessage: String = ""
    
    // Slash commands
    @State private var showCommandSuggestions: Bool = false
    @State private var commandSuggestions: [SlashCommandHandler.CommandSuggestion] = []
    
    // Keyboard Monitor
    @StateObject private var keyboardMonitor = KeyboardMonitor()
    
    // Theme
    private let gradient = LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    private var inputFieldBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .shadow(color: isProcessing ? .purple.opacity(0.3) : .clear, radius: isProcessing ? 15 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: isProcessing ? [.blue, .purple] : [.white.opacity(0.2), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isProcessing ? 2 : 1
                    )
                    .opacity(isProcessing ? 0.8 : 1.0)
                    .animation(isProcessing ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: isProcessing)
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
                    .onChange(of: query) {
                        updateCommandSuggestions(for: query)
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
            
            // MARK: - Briefing Cards (JSON)
            if !briefings.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 16) {
                        ForEach(briefings) { briefing in
                            VStack(alignment: .leading, spacing: 12) {
                                // Header
                                HStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 8, height: 8)
                                    Text(briefing.time)
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text(briefing.title)
                                    .font(.headline)
                                    .lineLimit(nil) // Allow multi-line title
                                
                                Text(briefing.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil) // Allow full summary
                                
                                Divider()
                                
                                ForEach(briefing.points, id: \.self) { point in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•").foregroundStyle(.tertiary)
                                        Text(point)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading) // Full width
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                    }
                    .padding(.horizontal, 4) // Minimal horizontal padding
                    .padding(.bottom, 24)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ViewHeightKey.self, value: geometry.size.height)
                    })
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // MARK: - Legacy Text Response
            if !response.isEmpty && briefings.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Measuring content size with background GeometryReader if needed, 
                    // or just letting ScrollView expand naturally within limits.
                    // For dynamic resizing, we notify the controller of the content height.
                    
                    ScrollView {
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
            
            // Auto-focus observer
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("SpotlightDidShow"),
                object: nil,
                queue: .main
            ) { _ in
                // Force reset focus
                isInputFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isInputFocused = true
                }
            }
        }
        .scaleEffect(isVisible ? 1.0 : 0.96)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: response)
        // Keyboard Backspace Observer
        .onReceive(keyboardMonitor.deletePublisher) {
            if query.isEmpty && (!response.isEmpty || !briefings.isEmpty) {
                withAnimation {
                    response = ""
                    briefings = []
                    commandSuggestions = []
                    showCommandSuggestions = false
                }
            }
        }
        // Slash Command Output Observer
        .onReceive(container.slashCommandHandler.outputPublisher) { output in
            if !output.isEmpty {
                withAnimation {
                    // Try to decode as cards
                    let cleaned = output
                        .replacingOccurrences(of: "```json", with: "")
                        .replacingOccurrences(of: "```", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let data = cleaned.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([Briefing].self, from: data) {
                        self.briefings = decoded
                        self.response = "" // Hide text response
                    } else {
                        // Fallback to text
                        self.briefings = []
                        self.response = output
                    }
                    
                    // Ensure input is cleared
                    query = ""
                }
            }
        }
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
        
        // Clear query but DON'T clear response yet (keep previous answer visible)
        // query = "" // DEFERRED until answer comes back
        withAnimation { isProcessing = true }
        
        Task {
            await performQuery(userQuery)
        }
    }
    

    
    private func performQuery(_ userQuery: String) async {
        print("🔍 Starting query: \(userQuery)")
        
        var clipboardContext: [RAGContextItem] = []
        
        // Search
        print("🔍 Searching clipboard...")
        let searchResults = await container.clippy.search(query: userQuery, limit: 5)
        let vectorIds = Set(searchResults.map { $0.0 })
        
        if !vectorIds.isEmpty {
            // Filter items matching the search results
            print("🔎 Available SwiftData items: \(allItems.count)")
            
            let relevantItems = allItems.filter { item in
                guard let itemVectorId = item.vectorId else { return false }
                // Print check for first few items
                return vectorIds.contains(itemVectorId)
            }
            
            if relevantItems.isEmpty && !vectorIds.isEmpty {
                 print("⚠️ Mismatch! Search found \(vectorIds.count) vectors but 0 SwiftData items matched.")
                 // Print first few SwiftData IDs to debug
                 let firstFewIDs = allItems.prefix(3).compactMap { $0.vectorId?.uuidString }
                 print("⚠️ First 3 SwiftData IDs: \(firstFewIDs)")
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
            let memories = await container.mem0Service.searchMemories(query: userQuery, limit: 3)
            print("🧠 Mem0 found \(memories.count) memories")
            
            let memoryItems = memories.map { memory in
                RAGContextItem(
                    content: memory.memory,
                    tags: ["memory"],
                    type: "memory",
                    timestamp: Date(),
                    title: "Long-term Memory"
                )
            }
            
            clipboardContext.append(contentsOf: memoryItems)
        }
        
        

        
        // Grok Generation
        print("🤖 Asking AI...")
        let conversationHistory = container.conversationManager.getFormattedHistory()
        
        // Logging handled via onReceive
        
        let answer = await container.grokService.generateAnswer(
            question: userQuery,
            clipboardContext: clipboardContext,
            appName: container.clipboardMonitor.currentAppName,
            conversationHistory: conversationHistory
        )
        
        await MainActor.run {
            withAnimation {
                isProcessing = false
                // Clear query now that answer is here
                if answer != nil { self.query = "" }
            }
            
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

// Keyboard Monitor
class KeyboardMonitor: ObservableObject {
    let deletePublisher = PassthroughSubject<Void, Never>()
    private var monitor: Any?
    
    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 51 is Backspace (Delete).
            if event.keyCode == 51 {
                self?.deletePublisher.send()
            }
            return event
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
