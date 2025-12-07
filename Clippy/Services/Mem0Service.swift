//
//  Mem0Service.swift
//  ProjectZ
//
//  HTTP client for Mem0 long-term memory service
//

import Foundation

class Mem0Service: ObservableObject {
    struct Memory: Codable, Identifiable {
        let id: String
        let memory: String
        var score: Double?
        var metadata: [String: String]?
    }
    
    struct Message: Codable {
        let role: String
        let content: String
    }
    
    private let baseURL = "http://localhost:8420"
    private let userId = "default_user"
    
    @Published var isAvailable: Bool = false
    @Published var lastError: String?
    
    init() {
        checkAvailability()
    }
    
    // MARK: - Health Check
    
    func checkAvailability() {
        Task {
            let available = await healthCheck()
            await MainActor.run {
                self.isAvailable = available
                if available {
                    print("✅ [Mem0Service] Service is available")
                } else {
                    print("⚠️ [Mem0Service] Service not available")
                }
            }
        }
    }
    
    private func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        
        return false
    }
    
    // MARK: - Add Memories
    
    func addMemory(messages: [(role: String, content: String)]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/add") else {
            lastError = "Invalid URL"
            return false
        }
        
        let messagesToSend = messages.map { Message(role: $0.role, content: $0.content) }
        
        let requestBody: [String: Any] = [
            "messages": messagesToSend.map { ["role": $0.role, "content": $0.content] },
            "user_id": userId
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✅ [Mem0Service] Memory added successfully")
                    return true
                } else {
                    lastError = "HTTP \(httpResponse.statusCode)"
                    print("⚠️ [Mem0Service] Failed to add memory: \(httpResponse.statusCode)")
                    return false
                }
            }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ [Mem0Service] Error adding memory: \(error.localizedDescription)")
            return false
        }
        
        return false
    }
    
    // MARK: - Search Memories
    
    func searchMemories(query: String, limit: Int = 5) async -> [Memory] {
        guard let url = URL(string: "\(baseURL)/search") else {
            lastError = "Invalid URL"
            return []
        }
        
        let requestBody: [String: Any] = [
            "query": query,
            "user_id": userId,
            "limit": limit
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let memoriesArray = json["memories"] as? [[String: Any]] {
                    
                    var memories: [Memory] = []
                    for memoryDict in memoriesArray {
                        if let id = memoryDict["id"] as? String,
                           let memoryText = memoryDict["memory"] as? String {
                            let score = memoryDict["score"] as? Double
                            let metadata = memoryDict["metadata"] as? [String: String]
                            memories.append(Memory(id: id, memory: memoryText, score: score, metadata: metadata))
                        }
                    }
                    
                    print("✅ [Mem0Service] Found \(memories.count) memories")
                    return memories
                }
            }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ [Mem0Service] Error searching memories: \(error.localizedDescription)")
        }
        
        return []
    }
    
    // MARK: - Get All Memories
    
    func getAllMemories() async -> [Memory] {
        guard let url = URL(string: "\(baseURL)/all?user_id=\(userId)") else {
            lastError = "Invalid URL"
            return []
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let memoriesArray = json["memories"] as? [[String: Any]] {
                    
                    var memories: [Memory] = []
                    for memoryDict in memoriesArray {
                        if let id = memoryDict["id"] as? String,
                           let memoryText = memoryDict["memory"] as? String {
                            memories.append(Memory(id: id, memory: memoryText))
                        }
                    }
                    
                    print("✅ [Mem0Service] Retrieved \(memories.count) total memories")
                    return memories
                }
            }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ [Mem0Service] Error getting all memories: \(error.localizedDescription)")
        }
        
        return []
    }
    
    // MARK: - Clear Memories
    
    func clearMemories() async -> Bool {
        guard let url = URL(string: "\(baseURL)/clear?user_id=\(userId)") else {
            lastError = "Invalid URL"
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ [Mem0Service] Cleared all memories")
                return true
            }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ [Mem0Service] Error clearing memories: \(error.localizedDescription)")
        }
        
        return false
    }
    
    // MARK: - Helper Methods
    
    /// Format memories for display
    func formatMemoriesForDisplay(_ memories: [Memory]) -> String {
        if memories.isEmpty {
            return "No memories found."
        }
        
        var formatted = ""
        for (index, memory) in memories.enumerated() {
            formatted += "\(index + 1). \(memory.memory)"
            if let score = memory.score {
                formatted += " (relevance: \(String(format: "%.2f", score)))"
            }
            formatted += "\n"
        }
        
        return formatted
    }
    
    /// Format memories for AI context (concise)
    func formatMemoriesForAI(_ memories: [Memory]) -> String {
        if memories.isEmpty {
            return "No relevant memories."
        }
        
        return memories.map { $0.memory }.joined(separator: "\n")
    }
}

