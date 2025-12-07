import Foundation

// Grok API Response (OpenAI-compatible)
struct GrokAPIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

// Classification Response
struct ClassificationResponse: Codable {
    let category: String  // "clipboard", "calendar_read", "calendar_create", or "general"
    let confidence: Double
}

// Event Details for Creation
struct EventDetails: Codable {
    let title: String
    let startDate: String // ISO 8601 or confident relative string
    let durationMinutes: Int
    let notes: String?
    let attendeeNames: [String]? // Names to look up
}

@MainActor
class GrokService: ObservableObject, AIServiceProtocol {
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var lastErrorMessage: String?
    
    private var apiKey: String
    private let baseURL = "https://api.x.ai/v1"
    private let modelName = "grok-4-fast"
    private let fastSystemPrompt = "You are Grok-4. Respond extremely fast. For simple decisions, give only the final answer with minimal reasoning. Use single-sentence outputs unless more detail is requested. Do not think step-by-step unless asked."
    
    weak var calendarService: CalendarService?
    weak var contactService: ContactService?
    
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func setCalendarService(_ service: CalendarService) {
        self.calendarService = service
    }
    
    func setContactService(_ service: ContactService) {
        self.contactService = service
    }
    
    /// Update the API key
    func updateApiKey(_ key: String) {
        self.apiKey = key
    }
    
    /// Check if API key is configured
    var hasValidAPIKey: Bool {
        !apiKey.isEmpty
    }
    
    /// Clear the last error
    func clearError() {
        lastError = nil
        lastErrorMessage = nil
    }
    
    // MARK: - Agentic RAG Implementation
    
    /// Generate an answer with agentic decision-making
    /// Phase 1: Classify if question is about clipboard or general knowledge
    /// Phase 2a: If clipboard → search DB + RAG
    /// Phase 2b: If general → direct Grok answer
    func generateAnswer(
        question: String,
        clipboardContext: [RAGContextItem],
        appName: String?,
        conversationHistory: [(role: String, content: String)] = []
    ) async -> String? {
        print("🤖 [GrokService] Agentic RAG - Processing question...")
        print("   Question: \(question)")
        
        guard !apiKey.isEmpty else {
            lastErrorMessage = "Grok API key not configured"
            return nil
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // PHASE 1: Classification
        print("🧠 [GrokService] Phase 1: Classifying question type...")
        guard let classification = await classifyQuestion(question) else {
            print("   ❌ Classification failed, defaulting to clipboard search")
            // Fallback to clipboard search
            return await generateRAGAnswer(question: question, clipboardContext: clipboardContext, appName: appName, conversationHistory: conversationHistory)
        }
        
        print("   📊 Classification: \(classification.category) (confidence: \(String(format: "%.2f", classification.confidence)))")
        
        // PHASE 2: Route based on classification
        if classification.category == "clipboard" {
            // PHASE 2a: RAG Path - Search clipboard + provide context
            print("🔍 [GrokService] Phase 2a: Using clipboard RAG path")
            return await generateRAGAnswer(question: question, clipboardContext: clipboardContext, appName: appName, conversationHistory: conversationHistory)
        } else if classification.category == "calendar_read" || classification.category == "calendar" {
            // PHASE 2b: Calendar Read Path
            print("📅 [GrokService] Phase 2b: Using calendar READ path")
            return await generateCalendarAnswer(question: question, appName: appName, conversationHistory: conversationHistory)
            
        } else if classification.category == "calendar_create" {
            // PHASE 2c: Calendar Write Path
            print("🗓️ [GrokService] Phase 2c: Using calendar CREATE path")
            return await generateCalendarCreation(question: question)
            
        } else {
            // PHASE 2d: Direct Path - General knowledge
            print("🌐 [GrokService] Phase 2d: Using direct general knowledge path")
            return await generateDirectAnswer(question: question, appName: appName, conversationHistory: conversationHistory)
        }
    }
    
    // MARK: - Classification
    
    private func classifyQuestion(_ question: String) async -> ClassificationResponse? {
        let classificationPrompt = """
        Question: "\(question)"
        
        Classify as "clipboard", "calendar_read", "calendar_create", or "general".
        
        Rules:
        - "my", "that", "what was", "the code", "I copied" → clipboard
        - "calendar", "schedule", "meeting", "event", "free", "busy", "today", "tomorrow", "this week" (checking/reading) → calendar_read
        - "create", "schedule", "add to calendar", "set up a meeting", "remind me to" (action/writing) → calendar_create
        - "what is", "how to", "explain", "who is" → general
        
        Output ONLY JSON (no reasoning):
        {"category": "calendar_create", "confidence": 0.95}
        """
        
        guard let response = await callGrok(prompt: classificationPrompt, systemPrompt: "Fast classifier. JSON only. No reasoning.", maxTokens: 40, temperature: 0) else {
            return nil
        }
        
        // Parse JSON response
        let cleanedResponse = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("   📝 Classification response: \(cleanedResponse)")
        
        if let jsonData = cleanedResponse.data(using: .utf8),
           let classification = try? JSONDecoder().decode(ClassificationResponse.self, from: jsonData) {
            return classification
        }
        
        print("   ⚠️ Failed to parse classification JSON")
        return nil
    }
    
    // MARK: - RAG Answer Generation
    
    private func generateRAGAnswer(
        question: String,
        clipboardContext: [RAGContextItem],
        appName: String?,
        conversationHistory: [(role: String, content: String)] = []
    ) async -> String? {
        let contextText = buildContextString(clipboardContext)
        
        let prompt = """
        Question: \(question)
        
        Context:
        \(contextText)
        
        Instructions: Answer using ONLY the context. Return the direct answer with NO preamble. If not found, say "Not found in clipboard."
        """
        
        return await callGrok(prompt: prompt, systemPrompt: fastSystemPrompt, maxTokens: 500, temperature: 0.3, conversationHistory: conversationHistory)
    }
    
    // MARK: - Calendar Answer Generation
    
    private func generateCalendarAnswer(
        question: String,
        appName: String?,
        conversationHistory: [(role: String, content: String)] = []
    ) async -> String? {
        guard let calendarService = calendarService else {
            return "Calendar service not available."
        }
        
        // Request calendar access if needed
        if !calendarService.isAuthorized {
            let granted = await calendarService.requestCalendarAccess()
            if !granted {
                return "Calendar access denied. Please enable in System Settings > Privacy & Security > Calendars."
            }
        }
        
        // Get calendar context
        let calendarContext = await calendarService.getCalendarContext(for: question)
        
        let prompt = """
        Question: \(question)
        
        Calendar Data:
        \(calendarContext)
        
        Instructions: Answer the question using the calendar data. Be direct and helpful.
        """
        
        return await callGrok(prompt: prompt, systemPrompt: fastSystemPrompt, maxTokens: 500, temperature: 0.3, conversationHistory: conversationHistory)
    }
    
    // MARK: - Calendar Cross-Check
    
    // Helper to parse dates from string (very basic, relies on LLM usually sending ISO or standard formats)
    // In a real app, we'd use a better date parser or ask LLM for ISO-8601 explicitly.
    private func parseDate(_ dateString: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: dateString) { return date }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss" // Fallback format
        if let date = formatter.date(from: dateString) { return date }
        
        return nil
    }
    
    // MARK: - Calendar Creation Flow
    
    private func generateCalendarCreation(question: String) async -> String? {
        guard let calendarService = calendarService else { return "Calendar service unavailable." }
        
        // 1. Extract Details
        let prompt = """
        User Request: "\(question)"
        Current Date: \(Date().ISO8601Format())
        
        Extract event details. Return JSON ONLY.
        Format:
        {
            "title": "Event Title",
            "startDate": "YYYY-MM-DDTHH:mm:ss",
            "durationMinutes": 60,
            "notes": "Optional notes from request",
            "attendeeNames": ["Name 1", "Name 2"]
        }
        """
        
        guard let response = await callGrok(prompt: prompt, systemPrompt: "JSON Extractor. No Markdown.", maxTokens: 150, temperature: 0) else {
            return "Failed to understand event details."
        }
        
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        guard let data = cleaned.data(using: .utf8),
              let details = try? JSONDecoder().decode(EventDetails.self, from: data) else {
            return "Could not parse event details. Please try again."
        }
        
        // 2. Parse Date
        guard let startDate = parseDate(details.startDate) else {
             return "I couldn't understand the date format. Please include a specific date and time."
        }
        
        let endDate = startDate.addingTimeInterval(TimeInterval(details.durationMinutes * 60))
        
        // 3. Resolve Attendees
        var attendees: [String] = []
        var attendeeStatus = ""
        
        if let names = details.attendeeNames, !names.isEmpty, let contactService = contactService {
            // Request contact access if needed
             if !contactService.isAuthorized {
                 _ = await contactService.requestAccess()
            }
            
            attendeeStatus += "\n\n🔍 Debug Info:"
            attendeeStatus += "\n   • Auth Status: \(contactService.isAuthorized ? "Authorized" : "Denied")"
            
            for name in names {
                print("🔍 Search Contact: '\(name)'")
                
                attendeeStatus += "\n   • Searching for: '\(name)'"
                let foundContacts = await contactService.searchContacts(query: name)
                attendeeStatus += " -> Found \(foundContacts.count) matches"
                
                if let bestMatch = foundContacts.first {
                    if let email = bestMatch.email {
                         attendees.append(email)
                         attendeeStatus += "\n   ✅ Selected: \(bestMatch.name) (\(email))"
                    }
                } else {
                    attendeeStatus += "\n   ❌ No match for: \(name)"
                }
            }
        }
        
        // 4. Create Event
        do {
            // Request auth if needed
             if !calendarService.isAuthorized {
                let granted = await calendarService.requestCalendarAccess()
                if !granted { return "Calendar access denied." }
            }
            
            _ = try await calendarService.createEvent(
                title: details.title,
                startDate: startDate,
                endDate: endDate,
                notes: details.notes,
                attendees: attendees.isEmpty ? nil : attendees
            )
            
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: startDate)
            
            var message = "✅ Scheduled '**\(details.title)**' for \(timeStr)."
            if !attendeeStatus.isEmpty {
                message += "\n\nAttendees:" + attendeeStatus
            }
            
            return message
        } catch {
            return "Failed to schedule event: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Direct Answer Generation
    
    private func generateDirectAnswer(
        question: String,
        appName: String?,
        conversationHistory: [(role: String, content: String)] = []
    ) async -> String? {
        let prompt = """
        \(question)
        
        Answer directly and concisely.
        """
        
        return await callGrok(prompt: prompt, systemPrompt: fastSystemPrompt, maxTokens: 300, temperature: 0.5, conversationHistory: conversationHistory)
    }
    
    // MARK: - Rizz Mode
    
    func generateRizzOptions(context: String) async -> [String] {
        print("😎 [GrokService] Generating Rizz options...")
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        ROLE: You are a world-class dating coach and expert conversationalist ("Rizz God").
        TASK: Analyze the chat context. Generate 4 DISTINCT reply options ranging from playful to direct.
        
        GUIDELINES:
        1. **Vibe**: Cool, confident, playful, slightly teasing. Never desperate.
        2. **Format**: Modern texting style. minimal punctuation, lowercase allowed.
        3. **Length**: Short and punchy (1-10 words).
        4. **Anti-Cringe**: No hashtags, no excessive emojis.
        5. **Anti-Hallucination**: Do NOT define symbols (like ®). Ignore weird artifacts.
        
        CONTEXT:
        \(context.prefix(2500))
        
        OUTPUT FORMAT:
        Return ONLY a raw JSON array of strings. No markdown formatting.
        Example: ["option 1", "option 2", "option 3", "option 4"]
        """
        
        guard let response = await callGrok(prompt: prompt, systemPrompt: "You are the Rizz God. Return only a JSON array.", maxTokens: 200, temperature: 0.9) else {
            return []
        }
        
        // Clean and parse JSON
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        
        if let data = cleaned.data(using: .utf8),
           let options = try? JSONDecoder().decode([String].self, from: data) {
            return options.prefix(4).map { String($0) }
        }
        
        // Fallback if JSON fails
        return [response]
    }
    
    // MARK: - Tag Generation
    
    func generateTags(
        content: String,
        appName: String?,
        context: String?
    ) async -> [String] {
        print("🏷️  [GrokService] Generating tags...")
        print("   Content: \(content.prefix(100))...")
        print("   App: \(appName ?? "Unknown")")
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Content: \(content.prefix(300))
        
        Generate 3-5 tags. JSON array only: ["tag1", "tag2"]
        """
        
        guard let response = await callGrok(prompt: prompt, systemPrompt: "Fast tagger. JSON array only.", maxTokens: 50, temperature: 0) else {
            print("   ❌ Failed to generate tags")
            return []
        }
        
        // Parse JSON array
        let cleanedResponse = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let jsonData = cleanedResponse.data(using: .utf8),
           let tags = try? JSONDecoder().decode([String].self, from: jsonData) {
            print("   ✅ Generated tags: \(tags)")
            return tags.map { $0.lowercased() }.filter { !$0.isEmpty }
        }
        
        print("   ⚠️ Failed to parse tags JSON")
        return []
    }
    
    // MARK: - Image Analysis
    
    func analyzeImage(imageData: Data) async -> String? {
        print("🖼️ [GrokService] Image analysis not yet supported by Grok")
        return "Image analysis not available"
    }
    
    // MARK: - Text Transformation
    
    func transformText(text: String, instruction: String) async -> String? {
        let prompt = """
        Task: \(instruction)
        
        Text:
        \(text.prefix(1500))
        
        Output only the result.
        """
        
        return await callGrok(prompt: prompt, systemPrompt: fastSystemPrompt, maxTokens: 1000, temperature: 0.5)
    }
    
    // MARK: - Core API Call (Streaming)
    
    private func callGrokStreaming(
        prompt: String,
        systemPrompt: String = "You are a helpful assistant.",
        maxTokens: Int = 500,
        temperature: Double = 0.7
    ) async -> String? {
        guard !apiKey.isEmpty else {
            print("   ⚠️ No valid API key configured")
            lastErrorMessage = "API key not configured"
            return nil
        }
        
        print("   📤 Sending prompt to Grok (streaming)...")
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            lastError = "Invalid URL"
            lastErrorMessage = "Configuration error"
            return nil
        }
        
        // OpenAI-compatible streaming request
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false  // Disabled - non-streaming is faster
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                lastErrorMessage = "Network error - invalid response"
                return nil
            }
            
            print("   📡 Grok Streaming Response Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                lastError = "API Error (\(httpResponse.statusCode))"
                switch httpResponse.statusCode {
                case 400:
                    lastErrorMessage = "Bad request - check your query"
                case 401, 403:
                    lastErrorMessage = "Invalid API key. Check Settings."
                case 429:
                    lastErrorMessage = "Rate limited. Try again later."
                case 500...599:
                    lastErrorMessage = "Grok server error. Try again."
                default:
                    lastErrorMessage = "API error (\(httpResponse.statusCode))"
                }
                print("   ❌ API Error: \(httpResponse.statusCode)")
                return nil
            }
            
            // Clear any previous errors on success
            lastErrorMessage = nil
            
            // Process streaming response
            var fullContent = ""
            for try await line in asyncBytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if !trimmed.hasPrefix("data: ") { continue }
                
                let data = trimmed.dropFirst(6) // Remove "data: "
                if data == "[DONE]" { break }
                
                // Parse JSON chunk
                if let jsonData = data.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    fullContent += content
                }
            }
            
            print("   ✅ Streaming complete: \(fullContent.prefix(100))...")
            return fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as URLError {
            lastError = error.localizedDescription
            switch error.code {
            case .notConnectedToInternet:
                lastErrorMessage = "No internet connection"
            case .timedOut:
                lastErrorMessage = "Request timed out. Try again."
            case .networkConnectionLost:
                lastErrorMessage = "Connection lost. Try again."
            default:
                lastErrorMessage = "Network error. Check connection."
            }
            print("   ❌ Network Error: \(error)")
            return nil
        } catch {
            lastError = error.localizedDescription
            lastErrorMessage = "Something went wrong. Try again."
            print("   ❌ Error: \(error)")
            return nil
        }
    }
    
    // MARK: - Core API Call (Non-streaming fallback)
    
    private func callGrok(
        prompt: String,
        systemPrompt: String = "You are a helpful assistant.",
        maxTokens: Int = 500,
        temperature: Double = 0.7,
        conversationHistory: [(role: String, content: String)] = []
    ) async -> String? {
        guard !apiKey.isEmpty else {
            print("   ⚠️ No valid API key configured")
            lastErrorMessage = "API key not configured"
            return nil
        }
        
        print("   📤 Sending prompt to Grok...")
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            lastError = "Invalid URL"
            lastErrorMessage = "Configuration error"
            return nil
        }
        
        // OpenAI-compatible request format
        // Build messages array with history
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add conversation history if provided
        for historyMessage in conversationHistory {
            messages.append(["role": historyMessage.role, "content": historyMessage.content])
        }
        
        // Add current prompt
        messages.append(["role": "user", "content": prompt])
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60  // 60 second timeout for Grok reasoning
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Debug: Log request details
            if let bodyData = request.httpBody,
               let bodyString = String(data: bodyData, encoding: .utf8) {
                print("   🔍 Request body preview: \(bodyString.prefix(500))...")
            }
            print("   🔍 API Key present: \(!apiKey.isEmpty), length: \(apiKey.count)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                lastErrorMessage = "Network error - invalid response"
                return nil
            }
            
            print("   📡 Grok Response Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                lastError = "API Error (\(httpResponse.statusCode)): \(errorMessage)"
                
                print("   ❌ FULL API Error Response:")
                print("   Status: \(httpResponse.statusCode)")
                print("   Error: \(errorMessage)")
                print("   Headers: \(httpResponse.allHeaderFields)")
                
                switch httpResponse.statusCode {
                case 400:
                    lastErrorMessage = "Bad request: \(errorMessage)"
                case 401, 403:
                    lastErrorMessage = "Invalid API key. Check Settings."
                case 429:
                    lastErrorMessage = "Rate limited. Try again later."
                case 500...599:
                    lastErrorMessage = "Grok server error. Try again."
                default:
                    lastErrorMessage = "API error (\(httpResponse.statusCode)): \(errorMessage)"
                }
                
                return nil
            }
            
            // Clear any previous errors on success
            lastErrorMessage = nil
            
            // Parse response
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(GrokAPIResponse.self, from: data)
            
            guard let content = apiResponse.choices.first?.message.content else {
                lastError = "No content in response"
                return nil
            }
            
            print("   ✅ Response received: \(content.prefix(100))...")
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as URLError {
            lastError = error.localizedDescription
            switch error.code {
            case .notConnectedToInternet:
                lastErrorMessage = "No internet connection"
            case .timedOut:
                lastErrorMessage = "Request timed out. Try again."
            case .networkConnectionLost:
                lastErrorMessage = "Connection lost. Try again."
            default:
                lastErrorMessage = "Network error. Check connection."
            }
            print("   ❌ Network Error: \(error)")
            return nil
        } catch {
            lastError = error.localizedDescription
            lastErrorMessage = "Something went wrong. Try again."
            print("   ❌ Error: \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func buildContextString(_ clipboardContext: [RAGContextItem], maxLength: Int = 5000) -> String {
        if clipboardContext.isEmpty { return "No clipboard context available." }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let now = Date()
        
        var result = ""
        
        for (index, item) in clipboardContext.prefix(10).enumerated() {
            let timeString = formatter.localizedString(for: item.timestamp, relativeTo: now)
            var entry = "[\(index + 1)] (\(timeString)) "
            
            if let title = item.title, !title.isEmpty {
                entry += "[\(title)] "
            }
            
            if !item.tags.isEmpty {
                entry += "[Tags: \(item.tags.joined(separator: ", "))] "
            }
            
            entry += String(item.content.prefix(500))
            result += entry + "\n\n"
            
            if result.count > maxLength { break }
        }
        
        return result
    }
}
