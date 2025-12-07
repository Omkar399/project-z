//
//  GuardianService.swift
//  ProjectZ
//
//  Guardian mode - monitors for messaging guarded contacts
//

import Foundation
import AppKit
import Combine

class GuardianService: ObservableObject {
    @Published var guardedContacts: [GuardedContact] = []
    @Published var isEnabled: Bool = true
    
    // Debug Mode
    @Published var isDebugMode: Bool = false
    @Published var lastAlignmentScore: Double = 0.0
    @Published var lastContext: String = ""
    
    // Goal Alignment
    @Published var currentGoal: String?
    private var goalEmbedding: [Double]?
    private let driftThreshold: Double = 0.4 // Adjust based on testing
    
    private var contextEngine: ContextEngine?
    private var spotlightController: SpotlightWindowController?
    private var grokService: GrokService?
    private var mem0Service: Mem0Service?
    
    private var appActivationObserver: NSObjectProtocol?
    private var appLaunchObserver: NSObjectProtocol?
    private var continuousMonitoringTimer: Timer?
    private var currentMonitoredApp: String?
    private var lastWarnedContact: String?
    private var lastDriftWarningTime: Date?
    
    // Supported apps for monitoring (contacts)
    private let supportedApps = [
        "Messages",
        "WhatsApp",
        "Telegram",
        "Signal"
    ]
    
    struct GuardedContact: Identifiable, Codable {
        let id: UUID
        var name: String
        var customNudge: String?
        var isEnabled: Bool
        
        init(name: String, customNudge: String? = nil, isEnabled: Bool = true) {
            self.id = UUID()
            self.name = name
            self.customNudge = customNudge
            self.isEnabled = isEnabled
        }
    }
    
    init() {
        loadGuardedContacts()
    }
    
    func setDependencies(contextEngine: ContextEngine, spotlightController: SpotlightWindowController, grokService: GrokService, mem0Service: Mem0Service) {
        self.contextEngine = contextEngine
        self.spotlightController = spotlightController
        self.grokService = grokService
        self.mem0Service = mem0Service
    }
    
    // MARK: - Goal Setting
    
    func setGoal(_ text: String) {
        guard !text.isEmpty else { return }
        
        print("🎯 [Guardian] Setting goal: \"\(text)\"")
        currentGoal = text
        
        // 1. Store in Mem0
        Task {
            let messages = [
                (role: "user", content: "I am setting a current focus goal: \(text)"),
                (role: "assistant", content: "Understood. I will help you stay focused on: \(text)")
            ]
            _ = await mem0Service?.addMemory(messages: messages)
        }
        
        // 2. Generate Embedding
        Task {
            if let embedding = await grokService?.getEmbedding(text: text) {
                await MainActor.run {
                    self.goalEmbedding = embedding
                    print("🎯 [Guardian] Goal embedding generated (dim: \(embedding.count))")
                    
                    // Start broad monitoring if not already
                    self.startMonitoring()
                }
            } else {
                print("⚠️ [Guardian] Failed to generate goal embedding")
            }
        }
    }
    
    func clearGoal() {
        print("🎯 [Guardian] Clearing goal")
        currentGoal = nil
        goalEmbedding = nil
        lastDriftWarningTime = nil
        
        // If no guarded contacts, we might want to stop monitoring, 
        // but let's leave that to the standard logic
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard isEnabled else {
            print("🛡️ [Guardian] Monitoring disabled")
            return
        }
        
        print("🛡️ [Guardian] Starting monitoring (Contacts: \(guardedContacts.count), Goal Active: \(currentGoal != nil))")
        
        // Listen for app activation events (when switching to an app)
        if appActivationObserver == nil {
            appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let appName = app.localizedName {
                    self.handleAppActivated(appName: appName)
                }
            }
        }
        
        // Listen for app launch events (when opening an app)
        if appLaunchObserver == nil {
            appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let appName = app.localizedName {
                    print("🛡️ [Guardian] \(appName) launched, will check shortly...")
                    // Wait longer for app to fully load and window to appear
                    self.handleAppActivated(appName: appName, delay: 1.5)
                }
            }
        }
        
        print("🛡️ [Guardian] Monitoring active")
        
        // Check if any monitored apps are already running
        checkAlreadyRunningApps()
    }
    
    func stopMonitoring() {
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        if let observer = appLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appLaunchObserver = nil
        }
        stopContinuousMonitoring()
        print("🛡️ [Guardian] Monitoring stopped")
    }
    
    private func checkAlreadyRunningApps() {
        // Check if any monitored apps are currently running and check their contacts
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let appName = app.localizedName, supportedApps.contains(appName) {
                print("🛡️ [Guardian] Found \(appName) already running, checking...")
                // Check with longer delay to be safe
                handleAppActivated(appName: appName, delay: 1.0)
            }
        }
    }
    
    private func handleAppActivated(appName: String, delay: Double = 0.3) {
        guard isEnabled else {
            stopContinuousMonitoring()
            return
        }
        
        // Check if we need to monitor this app
        let isSupportedApp = supportedApps.contains(appName)
        let isGoalActive = currentGoal != nil
        
        // If neither goal monitoring nor contact monitoring applies, stop.
        // Actually, if goal is active, we monitor ALL apps to detect drift (e.g. Twitter, YouTube)
        if !isSupportedApp && !isGoalActive {
            stopContinuousMonitoring()
            return
        }
        
        print("🛡️ [Guardian] \(appName) activated/launched, checking context...")
        
        // Start continuous monitoring for this app
        startContinuousMonitoring(for: appName)
        
        // Check immediately after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkContext(in: appName)
        }
    }
    
    private func startContinuousMonitoring(for appName: String) {
        // Stop existing timer if any
        stopContinuousMonitoring()
        
        currentMonitoredApp = appName
        
        // Check interval: 0.3s for contacts, maybe slower for goals (e.g. 2.0s) to save API calls/battery?
        // But for "Judge-Melting" demo, 0.3s is impressive. Let's stick to 1.0s for goal to be safe on rate limits.
        let interval = (currentGoal != nil) ? 2.0 : 0.5
        
        continuousMonitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Verify the app is still frontmost
            if let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName,
               frontApp == appName {
                self.checkContext(in: appName)
            } else {
                // App is no longer frontmost, stop monitoring
                print("🛡️ [Guardian] \(appName) no longer frontmost, stopping continuous monitoring")
                self.stopContinuousMonitoring()
            }
        }
        
        print("🛡️ [Guardian] Continuous monitoring started for \(appName) (interval: \(interval)s)")
    }
    
    private func stopContinuousMonitoring() {
        continuousMonitoringTimer?.invalidate()
        continuousMonitoringTimer = nil
        if let app = currentMonitoredApp {
            print("🛡️ [Guardian] Stopped continuous monitoring for \(app)")
        }
        currentMonitoredApp = nil
    }
    
    private func checkContext(in appName: String) {
        guard let contextEngine = contextEngine else { return }
        
        // 1. Get Context
        let context = contextEngine.getCurrentContext()
        
        // 2. Check Guarded Contacts (if supported app)
        if supportedApps.contains(appName) {
            checkContactContext(context, appName: appName)
        }
        
        // 3. Check Goal Alignment (if goal set)
        if currentGoal != nil {
            checkGoalAlignment(context, appName: appName)
        }
    }
    
    private func checkContactContext(_ context: ContextEngine.AppContext, appName: String) {
        // Extract potential contact name from window title or UI element
        let potentialContact = extractContactName(from: context, appName: appName)
        
        guard let contactName = potentialContact else {
            // Clear last warned contact if no contact is visible
            lastWarnedContact = nil
            return
        }
        
        // Check if this contact is guarded
        if let guardedContact = findGuardedContact(matching: contactName) {
            // Only trigger if we haven't already warned about this contact
            if lastWarnedContact != contactName {
                print("🚨 [Guardian] GUARDED CONTACT DETECTED: \(guardedContact.name)")
                lastWarnedContact = contactName
                triggerIntervention(for: guardedContact, in: appName)
            }
        } else {
            // Not a guarded contact, clear last warned
            lastWarnedContact = nil
        }
    }
    
    private func checkGoalAlignment(_ context: ContextEngine.AppContext, appName: String) {
        guard let goalEmbedding = goalEmbedding, let grokService = grokService else { return }
        
        // Rate limit checks (e.g., don't check every single frame if we just warned)
        if let lastWarn = lastDriftWarningTime, Date().timeIntervalSince(lastWarn) < 600 { // 10 min snooze
            return
        }
        
        // Build rich context string for embedding
        var contextString = "App: \(appName)"
        if let title = context.windowTitle { contextString += " | Window: \(title)" }
        // We might want more text from accessibility if available, but let's start with title/app
        
        // Skip check if context is too sparse
        if contextString.count < 10 { return }
        
        Task {
            // Generate embedding for current context
            if let currentEmbedding = await grokService.getEmbedding(text: contextString) {
                let similarity = cosineSimilarity(goalEmbedding, currentEmbedding)
                
                await MainActor.run {
                    self.lastAlignmentScore = similarity
                    self.lastContext = contextString
                    if self.isDebugMode {
                         print("📉 [Guardian Debug] Alignment: \(String(format: "%.2f", similarity * 100))% | Context: \(contextString)")
                    } else {
                        print("📉 [Guardian] Goal Alignment: \(String(format: "%.2f", similarity * 100))% | Context: \(contextString)")
                    }
                }
                
                if similarity < driftThreshold {
                    await MainActor.run {
                        // Double check we haven't warned recently inside the task
                        if let lastWarn = self.lastDriftWarningTime, Date().timeIntervalSince(lastWarn) < 600 { return }
                        
                        print("🚨 [Guardian] DRIFT DETECTED! Alignment: \(similarity)")
                        self.triggerGoalWarning(similarity: similarity, currentContext: contextString)
                        self.lastDriftWarningTime = Date()
                    }
                }
            }
        }
    }
    
    // MARK: - Vector Math
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 0 else { return 0.0 }
        
        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        if normA == 0 || normB == 0 { return 0.0 }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
    
    private func extractContactName(from context: ContextEngine.AppContext, appName: String) -> String? {
        // Try window title first
        if let windowTitle = context.windowTitle, !windowTitle.isEmpty {
            // Clean up window title (remove app name suffixes, etc.)
            let cleaned = windowTitle
                .replacingOccurrences(of: " — Messages", with: "")
                .replacingOccurrences(of: " - WhatsApp", with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces)
            
            // Skip generic titles
            if cleaned != appName && cleaned != "Messages" && cleaned != "WhatsApp" {
                return cleaned
            }
        }
        
        // Try focused element text (chat header)
        if let focusedElement = context.focusedElement, !focusedElement.isEmpty {
            return focusedElement
        }
        
        return nil
    }
    
    private func findGuardedContact(matching contactName: String) -> GuardedContact? {
        return guardedContacts.first { contact in
            contact.isEnabled && contactName.lowercased().contains(contact.name.lowercased())
        }
    }
    
    // MARK: - Intervention
    
    private func triggerGoalWarning(similarity: Double, currentContext: String) {
        guard let goal = currentGoal else { return }
        
        let percentage = Int(similarity * 100)
        
        DispatchQueue.main.async { [weak self] in
            self?.spotlightController?.showGoalWarning(
                goal: goal,
                currentContext: currentContext,
                alignment: percentage
            )
        }
    }
    
    private func triggerIntervention(for contact: GuardedContact, in appName: String) {
        print("🚨 [Guardian] Triggering intervention for \(contact.name)")
        
        // Prepare nudge message
        let nudgeMessage = contact.customNudge ?? generateDefaultNudge(for: contact.name, app: appName)
        
        // Show Spotlight with nudge
        DispatchQueue.main.async { [weak self] in
            self?.spotlightController?.showWithNudge(message: nudgeMessage)
        }
    }
    
    private func generateDefaultNudge(for contactName: String, app: String) -> String {
        let messages = [
            "Hold up - you're about to message \(contactName). Want to take a moment?",
            "Hey, you're messaging \(contactName). Remember why you decided to step back?",
            "Pause - you're about to reach out to \(contactName). Is this what you really want?",
            "Wait - \(contactName) is a guarded contact. Take a breath before continuing.",
            "Friendly reminder: You set a boundary around \(contactName). Still want to proceed?"
        ]
        
        return messages.randomElement() ?? messages[0]
    }
    
    // MARK: - Contact Management
    
    func addGuardedContact(name: String, customNudge: String? = nil) {
        let contact = GuardedContact(name: name, customNudge: customNudge)
        guardedContacts.append(contact)
        saveGuardedContacts()
        print("🛡️ [Guardian] Added guarded contact: \(name)")
    }
    
    func removeGuardedContact(id: UUID) {
        guardedContacts.removeAll { $0.id == id }
        saveGuardedContacts()
        print("🛡️ [Guardian] Removed guarded contact")
    }
    
    func updateGuardedContact(id: UUID, name: String? = nil, customNudge: String? = nil, isEnabled: Bool? = nil) {
        if let index = guardedContacts.firstIndex(where: { $0.id == id }) {
            if let name = name {
                guardedContacts[index].name = name
            }
            if let customNudge = customNudge {
                guardedContacts[index].customNudge = customNudge
            }
            if let isEnabled = isEnabled {
                guardedContacts[index].isEnabled = isEnabled
            }
            saveGuardedContacts()
        }
    }
    
    func resetLastWarnedContact() {
        lastWarnedContact = nil
        print("🛡️ [Guardian] Reset last warned contact - can warn again")
    }
    
    func snoozeGoalWarning() {
        print("⏳ [Guardian] Snoozing goal warning for 10 minutes")
        lastDriftWarningTime = Date() // Reset to now, timer logic handles the check
    }
    
    func restoreFocus() {
        // Logic to switch back to productive app could go here
        // For now, just acknowledged
        print("🔁 [Guardian] Focus restored user action")
        // Maybe reset snooze to allow immediate warning if they drift again instantly?
        // Or keep a grace period? Let's keep grace period small.
        lastDriftWarningTime = Date().addingTimeInterval(-540) // 9 mins ago, so warns in 1 min if still drifting
    }
    
    // MARK: - Persistence
    
    private func saveGuardedContacts() {
        if let encoded = try? JSONEncoder().encode(guardedContacts) {
            UserDefaults.standard.set(encoded, forKey: "GuardedContacts")
        }
    }
    
    private func loadGuardedContacts() {
        if let data = UserDefaults.standard.data(forKey: "GuardedContacts"),
           let decoded = try? JSONDecoder().decode([GuardedContact].self, from: data) {
            guardedContacts = decoded
            print("🛡️ [Guardian] Loaded \(guardedContacts.count) guarded contacts")
        }
    }
    
    deinit {
        stopMonitoring()
    }
}

