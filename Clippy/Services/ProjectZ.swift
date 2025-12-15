import Foundation
import SwiftData

@MainActor
class ProjectZ: ObservableObject {
    @Published var isInitialized = false
    @Published var statusMessage = "Initializing embedding service..."
    
    // Simple in-memory vector store
    private var documents: [(id: UUID, text: String, embedding: [Float])] = []
    
    func initialize() async {
        print("🚀 [ProjectZ] Initializing model2vec embeddings...")
        
        // For now, use a simple TF-IDF approximation until we add model2vec package
        // This allows the app to work immediately
        isInitialized = true
        statusMessage = "Ready (In-Memory Search)"
        print("✅ [ProjectZ] Initialized successfully with in-memory search")
        print("   Note: Using simple text matching until model2vec is integrated")
    }
    
    func addDocument(vectorId: UUID, text: String) async {
        await addDocuments(items: [(vectorId, text)])
    }
    
    func addDocuments(items: [(UUID, String)]) async {
        guard isInitialized else {
            print("⚠️ [ProjectZ] Cannot add documents - not initialized")
            return
        }
        
        let count = items.count
        print("📝 [ProjectZ] Adding \(count) documents...")
        
        for (id, text) in items {
            // Simple bag-of-words embedding (temporary until model2vec)
            let embedding = createSimpleEmbedding(text: text)
            documents.append((id: id, text: text, embedding: embedding))
        }
        
        print("   ✅ Added \(count) documents (total: \(documents.count))")
    }
    
    func search(query: String, limit: Int = 10) async -> [(UUID, Float)] {
        guard isInitialized else {
            print("⚠️ [ProjectZ] Cannot search - not initialized")
            return []
        }
        
        print("🔎 [ProjectZ] Searching for: '\(query)' (limit: \(limit))")
        
        let queryEmbedding = createSimpleEmbedding(text: query)
        
        // Calculate cosine similarity with all documents
        var results: [(UUID, Float)] = []
        for doc in documents {
            let similarity = cosineSimilarity(queryEmbedding, doc.embedding)
            results.append((doc.id, similarity))
        }
        
        // Sort by similarity (descending) and take top results
        results.sort { $0.1 > $1.1 }
        let topResults = Array(results.prefix(limit))
        
        print("   ✅ Found \(topResults.count) results")
        for (index, result) in topResults.prefix(5).enumerated() {
            print("      \(index + 1). ID: \(result.0), Score: \(String(format: "%.3f", result.1))")
        }
        
        return topResults
    }
    
    func deleteDocument(vectorId: UUID) async throws {
        documents.removeAll { $0.id == vectorId }
    }
    
    // MARK: - Simple Embedding (Temporary)
    
    private func createSimpleEmbedding(text: String) -> [Float] {
        // Simple bag-of-words with TF weighting
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        // Create a fixed-size embedding vector (128 dimensions)
        var embedding = [Float](repeating: 0, count: 128)
        
        for (index, word) in words.enumerated() {
            // Hash each word to a dimension
            let hash = abs(word.hashValue % 128)
            embedding[hash] += 1.0 / Float(words.count)
        }
        
        // Normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }
        
        return embedding
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let magnitudeB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}
