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
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isProcessing ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Response area - fades in when response arrives (no ScrollView!)
            if !response.isEmpty {
                Text(response)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .id(response) // Force refresh when response changes
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
        }
    }
    
    // MARK: - Actions
    
    private func handleQuery() {
        guard !query.isEmpty, !isProcessing else { return }
        
        let userQuery = query
        
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
        
        // Send to Grok with agentic RAG
        log("🤖 Calling Grok API...")
        let answer = await container.grokService.generateAnswer(
            question: userQuery,
            clipboardContext: clipboardContext,
            appName: container.clipboardMonitor.currentAppName
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

