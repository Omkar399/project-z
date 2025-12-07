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
    
    private var contextEngine: ContextEngine?
    private var spotlightController: SpotlightWindowController?
    private var appActivationObserver: NSObjectProtocol?
    private var appLaunchObserver: NSObjectProtocol?
    private var continuousMonitoringTimer: Timer?
    private var currentMonitoredApp: String?
    private var lastWarnedContact: String?
    
    // Supported apps for monitoring
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
    
    func setDependencies(contextEngine: ContextEngine, spotlightController: SpotlightWindowController) {
        self.contextEngine = contextEngine
        self.spotlightController = spotlightController
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard isEnabled else {
            print("🛡️ [Guardian] Monitoring disabled")
            return
        }
        
        print("🛡️ [Guardian] Starting monitoring for \(guardedContacts.count) contacts")
        
        // Listen for app activation events (when switching to an app)
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
        
        // Listen for app launch events (when opening an app)
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
        
        print("🛡️ [Guardian] Monitoring active (activation + launch)")
        
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
        
        // If switching to a non-monitored app, stop continuous monitoring
        guard supportedApps.contains(appName) else {
            stopContinuousMonitoring()
            return
        }
        
        guard !guardedContacts.isEmpty else {
            stopContinuousMonitoring()
            return
        }
        
        print("🛡️ [Guardian] \(appName) activated/launched, starting continuous monitoring...")
        
        // Start continuous monitoring for this app
        startContinuousMonitoring(for: appName)
        
        // Check immediately after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkCurrentContact(in: appName)
        }
    }
    
    private func startContinuousMonitoring(for appName: String) {
        // Stop existing timer if any
        stopContinuousMonitoring()
        
        currentMonitoredApp = appName
        
        // Check every 0.3 seconds while the app is frontmost
        continuousMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Verify the app is still frontmost
            if let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName,
               frontApp == appName {
                self.checkCurrentContact(in: appName)
            } else {
                // App is no longer frontmost, stop monitoring
                print("🛡️ [Guardian] \(appName) no longer frontmost, stopping continuous monitoring")
                self.stopContinuousMonitoring()
            }
        }
        
        print("🛡️ [Guardian] Continuous monitoring started for \(appName) (checking every 0.3s)")
    }
    
    private func stopContinuousMonitoring() {
        continuousMonitoringTimer?.invalidate()
        continuousMonitoringTimer = nil
        if let app = currentMonitoredApp {
            print("🛡️ [Guardian] Stopped continuous monitoring for \(app)")
        }
        currentMonitoredApp = nil
    }
    
    private func checkCurrentContact(in appName: String) {
        guard let contextEngine = contextEngine else {
            print("⚠️ [Guardian] ContextEngine not available")
            return
        }
        
        // Use ContextEngine to get current window/conversation context
        let context = contextEngine.getCurrentContext()
        
        // Extract potential contact name from window title or UI element
        let potentialContact = extractContactName(from: context, appName: appName)
        
        guard let contactName = potentialContact else {
            print("🛡️ [Guardian] No contact detected in \(appName)")
            // Clear last warned contact if no contact is visible
            lastWarnedContact = nil
            return
        }
        
        print("🛡️ [Guardian] Current contact: \(contactName)")
        
        // Check if this contact is guarded
        if let guardedContact = findGuardedContact(matching: contactName) {
            // Only trigger if we haven't already warned about this contact
            if lastWarnedContact != contactName {
                print("🚨 [Guardian] GUARDED CONTACT DETECTED: \(guardedContact.name)")
                lastWarnedContact = contactName
                triggerIntervention(for: guardedContact, in: appName)
            } else {
                print("🛡️ [Guardian] Already warned about \(contactName), skipping")
            }
        } else {
            // Not a guarded contact, clear last warned
            lastWarnedContact = nil
        }
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

